import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/grade_model.dart';
import '../models/subject_model.dart';
import '../models/curriculum_model.dart';
import 'local_curriculum_data.dart';

/// Public reads only — write access is restricted to admins by
/// firestore.rules; see firebase/firestore.rules.
///
/// Every watch* stream falls back to the bundled local dataset
/// (local_curriculum_data.dart) whenever Firestore errors (e.g. rules not
/// yet deployed on the live project) or returns no data (e.g. not yet
/// seeded) — so Curriculum always shows verified content instead of an
/// error screen. Firestore data is preferred whenever it's actually there.
class CurriculumRepository {
  final FirebaseFirestore _db;
  CurriculumRepository(this._db);

  Stream<List<GradeModel>> watchGrades() async* {
    final local = await LocalCurriculumData.grades();
    final remote = _db
        .collection(AppConstants.collectionGrades)
        .where('active', isEqualTo: true)
        .orderBy('sortOrder')
        .snapshots()
        .map((s) => s.docs.map(GradeModel.fromDoc).toList());
    yield* _withLocalFallback(remote, local);
  }

  Stream<List<SubjectModel>> watchSubjectsForGrade(String gradeId) async* {
    final local = (await LocalCurriculumData.subjects())
        .where((s) => s.active && s.gradeIds.contains(gradeId))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final remote = _db
        .collection(AppConstants.collectionSubjects)
        .where('active', isEqualTo: true)
        .where('gradeIds', arrayContains: gradeId)
        .orderBy('sortOrder')
        .snapshots()
        .map((s) => s.docs.map(SubjectModel.fromDoc).toList());
    yield* _withLocalFallback(remote, local);
  }

  Stream<List<CurriculumModel>> watchUnits({
    required String gradeId,
    required String subjectId,
    required String semester,
  }) async* {
    final local = (await LocalCurriculumData.curriculum())
        .where((c) => c.gradeId == gradeId && c.subjectId == subjectId && c.semester == semester)
        .toList()
      ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));
    final remote = _db
        .collection(AppConstants.collectionCurriculum)
        .where('gradeId', isEqualTo: gradeId)
        .where('subjectId', isEqualTo: subjectId)
        .where('semester', isEqualTo: semester)
        .orderBy('unitNumber')
        .snapshots()
        .map((s) => s.docs.map(CurriculumModel.fromDoc).toList());
    yield* _withLocalFallback(remote, local);
  }

  Future<CurriculumModel?> getUnit(String curriculumId) async {
    try {
      final doc = await _db.collection(AppConstants.collectionCurriculum).doc(curriculumId).get();
      if (doc.exists) return CurriculumModel.fromDoc(doc);
    } catch (_) {
      // fall through to local lookup below
    }
    final local = await LocalCurriculumData.curriculum();
    for (final unit in local) {
      if (unit.curriculumId == curriculumId) return unit;
    }
    return null;
  }

  /// Prefers [remote] emissions; substitutes [local] for any emission that
  /// is empty, and falls back to [local] entirely if [remote] errors.
  Stream<List<T>> _withLocalFallback<T>(Stream<List<T>> remote, List<T> local) async* {
    try {
      await for (final list in remote) {
        yield list.isEmpty ? local : list;
      }
    } catch (_) {
      yield local;
    }
  }
}

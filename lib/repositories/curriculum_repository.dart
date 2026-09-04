import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/firestore_error_logger.dart';
import '../core/utils/firestore_fallback.dart';
import '../models/grade_model.dart';
import '../models/subject_model.dart';
import '../models/curriculum_model.dart';
import 'local_curriculum_data.dart';

/// Public reads only — write access is restricted to admins by
/// firestore.rules; see firebase/firestore.rules.
///
/// watchGrades/watchSubjectsForGrade fall back to the bundled local dataset
/// (local_curriculum_data.dart) whenever Firestore errors OR returns no
/// data — grades/subjects have no verification concept, so "empty" and
/// "unreachable" are treated the same. watchUnits/watchAllUnitsForSubject
/// only return needsVerification == false units and only fall back to
/// local data on a real Firestore error — an empty (nothing verified yet)
/// result is shown as empty, not papered over; see CurriculumAdminService
/// for how a unit gets verified.
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
    yield* withLocalFallback('CurriculumRepository.watchGrades', remote, local);
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
    yield* withLocalFallback('CurriculumRepository.watchSubjectsForGrade', remote, local);
  }

  /// Publicly visible units only (needsVerification == false) — an admin
  /// must verify a freshly-imported unit (see CurriculumAdminService)
  /// before it appears here. `substituteOnEmpty: false` because "zero
  /// verified units yet" is a real, honest state (not the same as
  /// Firestore being unreachable) — it should show as empty, not get
  /// papered over with the bundled fallback's unverified content.
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
        .where('needsVerification', isEqualTo: false)
        .orderBy('unitNumber')
        .snapshots()
        .map((s) => s.docs.map(CurriculumModel.fromDoc).toList());
    yield* withLocalFallback('CurriculumRepository.watchUnits', remote, local, substituteOnEmpty: false);
  }

  /// All publicly visible units (needsVerification == false) for a
  /// grade/subject across both semesters, in syllabus order — e.g. for a
  /// combined "All Units" view. Existing screens still use [watchUnits]
  /// per-semester; this is additive, not a replacement. Same
  /// empty-is-honest reasoning as [watchUnits] applies here.
  Stream<List<CurriculumModel>> watchAllUnitsForSubject({
    required String gradeId,
    required String subjectId,
  }) async* {
    final local = (await LocalCurriculumData.curriculum())
        .where((c) => c.gradeId == gradeId && c.subjectId == subjectId)
        .toList()
      ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));
    final remote = _db
        .collection(AppConstants.collectionCurriculum)
        .where('gradeId', isEqualTo: gradeId)
        .where('subjectId', isEqualTo: subjectId)
        .where('needsVerification', isEqualTo: false)
        .orderBy('unitNumber')
        .snapshots()
        .map((s) => s.docs.map(CurriculumModel.fromDoc).toList());
    yield* withLocalFallback('CurriculumRepository.watchAllUnitsForSubject', remote, local, substituteOnEmpty: false);
  }

  Future<CurriculumModel?> getUnit(String curriculumId) async {
    try {
      final doc = await _db.collection(AppConstants.collectionCurriculum).doc(curriculumId).get();
      if (doc.exists) return CurriculumModel.fromDoc(doc);
    } catch (e, st) {
      logFirestoreError('CurriculumRepository.getUnit', e, st);
      // fall through to local lookup below
    }
    final local = await LocalCurriculumData.curriculum();
    for (final unit in local) {
      if (unit.curriculumId == curriculumId) return unit;
    }
    return null;
  }
}

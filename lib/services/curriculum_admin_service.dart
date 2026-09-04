import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../models/curriculum_model.dart';
import '../repositories/local_curriculum_data.dart';

/// Admin-only curriculum operations: seeding bundled records into the live
/// `curriculum` collection (see local_curriculum_data.dart /
/// scripts/seed/curriculum.json — real data taken from the official DCTE
/// semester notification, not invented), and verifying/publishing them
/// (flipping needsVerification so CurriculumRepository.watchUnits, the
/// public query, starts showing them).
///
/// Requires the signed-in user to satisfy firestore.rules's admin check for
/// `curriculum/{curriculumId}` writes — currently either the `admin` custom
/// claim OR the temporary email whitelist (see AppConstants.adminEmails and
/// firebase/firestore.rules's isAdminOrWhitelistedForCurriculum()); a
/// caller matching neither gets a clean permission-denied.
class CurriculumAdminService {
  final FirebaseFirestore _db;
  CurriculumAdminService(this._db);

  /// Writes every bundled unit for [gradeId]/[subjectId] that doesn't
  /// already exist in the live `curriculum` collection, using deterministic
  /// doc IDs `unit_01`, `unit_02`, ... (per [unitDocId]) so re-running this
  /// never creates duplicates. Existing documents are left untouched
  /// (checked individually before writing).
  ///
  /// NOTE: `unit_01`..`unit_11` are unique only *within one grade+subject*.
  /// If this seeding pattern is later reused for another grade/subject in
  /// the same flat `curriculum` collection, that caller must use a
  /// different ID scheme (e.g. prefix with gradeId/subjectId) — otherwise
  /// its "unit_01" would silently overwrite this one's.
  Future<CurriculumSeedResult> seedBundledUnits({
    required String gradeId,
    required String subjectId,
  }) async {
    final allLocal = await LocalCurriculumData.curriculum();
    final units = allLocal.where((u) => u.gradeId == gradeId && u.subjectId == subjectId).toList()
      ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));

    if (units.isEmpty) {
      return CurriculumSeedResult(imported: 0, alreadyPresent: 0, total: 0);
    }

    final collection = _db.collection(AppConstants.collectionCurriculum);
    var imported = 0;
    var alreadyPresent = 0;

    for (final unit in units) {
      final docRef = collection.doc(unitDocId(unit.unitNumber));
      final existing = await docRef.get();
      if (existing.exists) {
        alreadyPresent++;
        continue;
      }
      await docRef.set(unit.toMap());
      imported++;
    }

    return CurriculumSeedResult(imported: imported, alreadyPresent: alreadyPresent, total: units.length);
  }

  static String unitDocId(int unitNumber) => 'unit_${unitNumber.toString().padLeft(2, '0')}';

  /// Every curriculum unit awaiting admin review (needsVerification ==
  /// true), across all grades/subjects — this is a single-field equality
  /// query, so it needs no composite index. Sorted client-side for a
  /// stable, readable admin list.
  Stream<List<CurriculumModel>> watchPendingUnits() {
    return _db
        .collection(AppConstants.collectionCurriculum)
        .where('needsVerification', isEqualTo: true)
        .snapshots()
        .map((s) {
      final units = s.docs.map(CurriculumModel.fromDoc).toList()
        ..sort((a, b) {
          final byGrade = a.gradeId.compareTo(b.gradeId);
          if (byGrade != 0) return byGrade;
          final bySubject = a.subjectId.compareTo(b.subjectId);
          if (bySubject != 0) return bySubject;
          return a.unitNumber.compareTo(b.unitNumber);
        });
      return units;
    });
  }

  /// Marks one unit verified (needsVerification -> false) so it becomes
  /// visible on the public Curriculum screen (see
  /// CurriculumRepository.watchUnits). Uses .update(), so every other
  /// field on the document (title, source attribution, etc.) is preserved
  /// — the record already lives in the public `curriculum` collection,
  /// there is nothing to move/copy.
  Future<void> verifyAndPublish(String curriculumId) async {
    await _db.collection(AppConstants.collectionCurriculum).doc(curriculumId).update({
      'needsVerification': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Verifies every still-pending unit for one grade/subject/semester in a
  /// single batch — e.g. "Verify All & Publish" for Grade 1 English
  /// Semester I. Returns how many were actually updated (0 if none were
  /// pending, so this is safe to press more than once).
  Future<int> verifyAllPending({
    required String gradeId,
    required String subjectId,
    required String semester,
  }) async {
    final snapshot = await _db
        .collection(AppConstants.collectionCurriculum)
        .where('gradeId', isEqualTo: gradeId)
        .where('subjectId', isEqualTo: subjectId)
        .where('semester', isEqualTo: semester)
        .where('needsVerification', isEqualTo: true)
        .get();

    if (snapshot.docs.isEmpty) return 0;

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'needsVerification': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return snapshot.docs.length;
  }
}

class CurriculumSeedResult {
  final int imported;
  final int alreadyPresent;
  final int total;
  const CurriculumSeedResult({required this.imported, required this.alreadyPresent, required this.total});
}

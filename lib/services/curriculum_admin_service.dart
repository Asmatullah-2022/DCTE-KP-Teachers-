import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../repositories/local_curriculum_data.dart';

/// Promotes bundled, already-extracted curriculum records (see
/// local_curriculum_data.dart / scripts/seed/curriculum.json — real data
/// taken from the official DCTE semester notification, not invented) into
/// the live `curriculum` collection, for admins to use instead of manually
/// typing every unit into the Firebase Console.
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
}

class CurriculumSeedResult {
  final int imported;
  final int alreadyPresent;
  final int total;
  const CurriculumSeedResult({required this.imported, required this.alreadyPresent, required this.total});
}

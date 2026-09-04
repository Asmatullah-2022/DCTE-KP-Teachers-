import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants/app_constants.dart';
import '../repositories/local_curriculum_data.dart';

/// Promotes bundled, already-extracted curriculum records (see
/// local_curriculum_data.dart / scripts/seed/curriculum.json — real data
/// taken from the official DCTE semester notification, not invented) into
/// the live `curriculum` collection, for admins to use instead of manually
/// typing every unit into the Firebase Console.
///
/// Requires the signed-in user to actually hold the `admin` custom claim —
/// firestore.rules only allows writes to `curriculum/{curriculumId}` when
/// `isAdmin()`, so a non-admin caller gets a clean permission-denied,
/// exactly like every other admin-only write path in this app (see
/// README.md §5, "Grant yourself admin").
class CurriculumAdminService {
  final FirebaseFirestore _db;
  CurriculumAdminService(this._db);

  /// Writes every bundled unit for [gradeId]/[subjectId] that doesn't
  /// already exist in the live `curriculum` collection. Existing documents
  /// are left untouched (checked individually before writing, so this is
  /// safe to run more than once). Returns how many were newly written vs.
  /// already present.
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
      final docRef = collection.doc(unit.curriculumId);
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
}

class CurriculumSeedResult {
  final int imported;
  final int alreadyPresent;
  final int total;
  const CurriculumSeedResult({required this.imported, required this.alreadyPresent, required this.total});
}

import 'dart:developer' as developer;

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
    final subscriptionId = DateTime.now().microsecondsSinceEpoch;
    developer.log(
      'CURRICULUM DEBUG: watchUnits() NEW SUBSCRIPTION #$subscriptionId '
      'gradeId="$gradeId" subjectId="$subjectId" semester="$semester" at ${DateTime.now()}',
      name: 'firestore',
    );

    await _debugCompareFilteredVsUnfiltered(gradeId: gradeId, subjectId: subjectId, semester: semester);

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
        .map((s) {
      developer.log(
        'CURRICULUM DEBUG: subscription #$subscriptionId RAW SNAPSHOT @ ${DateTime.now()} — '
        '${s.docs.length} doc(s), isFromCache=${s.metadata.isFromCache}, '
        'hasPendingWrites=${s.metadata.hasPendingWrites}, '
        'titles=${s.docs.map((d) => d.data()['unitTitle']).toList()}',
        name: 'firestore',
      );
      return s.docs.map(CurriculumModel.fromDoc).toList();
    });
    yield* withLocalFallback('CurriculumRepository.watchUnits#$subscriptionId', remote, local, substituteOnEmpty: false);
  }

  /// TEMPORARY — richer version of [watchUnits] for the on-screen debug
  /// panel (see SemesterUnitsScreen): same query, same honest-empty
  /// behavior (only falls back to local on a real error, never on a
  /// legitimate empty result), but yields a [CurriculumDebugSnapshot]
  /// carrying exactly what's needed to show on-device without adb: which
  /// source produced this emission (Firestore vs. the bundled fallback),
  /// cache/pending-write flags, an emission counter, and a timestamp. The
  /// screen uses this as its ONLY subscription (not in addition to
  /// [watchUnits]) so there's exactly one Firestore listener, not two.
  /// Remove this method (and CurriculumDebugSnapshot) once diagnosed.
  Stream<CurriculumDebugSnapshot> watchUnitsWithDebugInfo({
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
        .snapshots();

    var emissionNumber = 0;
    try {
      await for (final snap in remote) {
        emissionNumber++;
        yield CurriculumDebugSnapshot(
          units: snap.docs.map(CurriculumModel.fromDoc).toList(),
          source: CurriculumDataSource.firestore,
          isFromCache: snap.metadata.isFromCache,
          hasPendingWrites: snap.metadata.hasPendingWrites,
          timestamp: DateTime.now(),
          emissionNumber: emissionNumber,
        );
      }
    } catch (e, st) {
      logFirestoreError('CurriculumRepository.watchUnitsWithDebugInfo', e, st);
      emissionNumber++;
      yield CurriculumDebugSnapshot(
        units: local,
        source: CurriculumDataSource.localFallback,
        isFromCache: false,
        hasPendingWrites: false,
        timestamp: DateTime.now(),
        emissionNumber: emissionNumber,
      );
    }
  }

  /// TEMPORARY diagnostic — not part of the app's normal query path. Runs
  /// two one-shot reads: (1) gradeId+subjectId+semester only, and (2) the
  /// same plus needsVerification==false, then logs every raw field of
  /// every doc found by (1) so a type/value mismatch (e.g. needsVerification
  /// stored as the string "false" instead of the boolean false, or a
  /// semester string that LOOKS like "Semester I" but isn't byte-identical)
  /// is visible directly instead of guessed at. Read via `adb logcat -s
  /// flutter` or Android Studio's Logcat, filter for "CURRICULUM DEBUG".
  /// Remove this method (and its one call site above) once diagnosed.
  Future<void> _debugCompareFilteredVsUnfiltered({
    required String gradeId,
    required String subjectId,
    required String semester,
  }) async {
    try {
      final unfiltered = await _db
          .collection(AppConstants.collectionCurriculum)
          .where('gradeId', isEqualTo: gradeId)
          .where('subjectId', isEqualTo: subjectId)
          .where('semester', isEqualTo: semester)
          .get();
      final filtered = await _db
          .collection(AppConstants.collectionCurriculum)
          .where('gradeId', isEqualTo: gradeId)
          .where('subjectId', isEqualTo: subjectId)
          .where('semester', isEqualTo: semester)
          .where('needsVerification', isEqualTo: false)
          .get();

      developer.log(
        'CURRICULUM DEBUG: gradeId="$gradeId" subjectId="$subjectId" semester="$semester" '
        '-> ${unfiltered.docs.length} doc(s) WITHOUT the needsVerification filter, '
        '${filtered.docs.length} doc(s) WITH it.',
        name: 'firestore',
      );
      for (final doc in unfiltered.docs) {
        final data = doc.data();
        developer.log(
          'CURRICULUM DEBUG: doc id="${doc.id}" fields=$data '
          '(needsVerification runtimeType=${data['needsVerification']?.runtimeType}, '
          'unitNumber runtimeType=${data['unitNumber']?.runtimeType})',
          name: 'firestore',
        );
      }
    } catch (e, st) {
      developer.log('CURRICULUM DEBUG: comparison query itself failed: $e', name: 'firestore', error: e, stackTrace: st);
    }
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

  /// TEMPORARY — one-shot reads for the raw-collection debug panel (see
  /// SemesterUnitsScreen). Runs the EXACT same filtered query as
  /// [watchUnits] (for a stable count to compare against) and a
  /// completely UNFILTERED read of the whole `curriculum` collection —
  /// no gradeId/subjectId/semester/needsVerification filters at all — so
  /// every document's raw field values and Dart runtime types are visible
  /// directly, instead of only what CurriculumModel.fromMap() happens to
  /// coerce them into (which would hide exactly the kind of type mismatch
  /// this is trying to catch). Remove once diagnosed.
  Future<CurriculumRawDebugResult> debugFetchFilteredVsUnfiltered({
    required String gradeId,
    required String subjectId,
    required String semester,
  }) async {
    final filteredSnap = await _db
        .collection(AppConstants.collectionCurriculum)
        .where('gradeId', isEqualTo: gradeId)
        .where('subjectId', isEqualTo: subjectId)
        .where('semester', isEqualTo: semester)
        .where('needsVerification', isEqualTo: false)
        .get();

    final unfilteredSnap = await _db.collection(AppConstants.collectionCurriculum).get();

    final docs = unfilteredSnap.docs.map((d) {
      final data = d.data();
      return CurriculumRawDoc(
        id: d.id,
        data: data,
        gradeId: data['gradeId'],
        gradeIdType: data['gradeId']?.runtimeType.toString(),
        subjectId: data['subjectId'],
        subjectIdType: data['subjectId']?.runtimeType.toString(),
        semester: data['semester'],
        semesterType: data['semester']?.runtimeType.toString(),
        needsVerification: data['needsVerification'],
        needsVerificationType: data['needsVerification']?.runtimeType.toString(),
        unitNumber: data['unitNumber'],
        unitNumberType: data['unitNumber']?.runtimeType.toString(),
        statusOrPublishedField: _findStatusOrPublishedField(data),
      );
    }).toList();

    return CurriculumRawDebugResult(
      filteredCount: filteredSnap.docs.length,
      unfilteredCount: unfilteredSnap.docs.length,
      docs: docs,
    );
  }

  /// Looks for any field that might be the "is this visible" flag under a
  /// name other than needsVerification — e.g. if a document was written
  /// with `status`/`isPublished`/`published` instead of (or in addition
  /// to) `needsVerification`, since those are never read by the real
  /// query and would otherwise be an invisible reason a doc looks right
  /// but never matches.
  String? _findStatusOrPublishedField(Map<String, dynamic> data) {
    for (final key in ['status', 'isPublished', 'published']) {
      if (data.containsKey(key)) return '$key = ${data[key]} (${data[key]?.runtimeType})';
    }
    return null;
  }
}

/// TEMPORARY — see [CurriculumRepository.watchUnitsWithDebugInfo].
enum CurriculumDataSource { firestore, localFallback }

/// TEMPORARY — see [CurriculumRepository.watchUnitsWithDebugInfo].
class CurriculumDebugSnapshot {
  final List<CurriculumModel> units;
  final CurriculumDataSource source;
  final bool isFromCache;
  final bool hasPendingWrites;
  final DateTime timestamp;
  final int emissionNumber;

  const CurriculumDebugSnapshot({
    required this.units,
    required this.source,
    required this.isFromCache,
    required this.hasPendingWrites,
    required this.timestamp,
    required this.emissionNumber,
  });
}

/// TEMPORARY — see [CurriculumRepository.debugFetchFilteredVsUnfiltered].
class CurriculumRawDoc {
  final String id;
  final Map<String, dynamic> data;
  final dynamic gradeId;
  final String? gradeIdType;
  final dynamic subjectId;
  final String? subjectIdType;
  final dynamic semester;
  final String? semesterType;
  final dynamic needsVerification;
  final String? needsVerificationType;
  final dynamic unitNumber;
  final String? unitNumberType;
  final String? statusOrPublishedField;

  const CurriculumRawDoc({
    required this.id,
    required this.data,
    required this.gradeId,
    required this.gradeIdType,
    required this.subjectId,
    required this.subjectIdType,
    required this.semester,
    required this.semesterType,
    required this.needsVerification,
    required this.needsVerificationType,
    required this.unitNumber,
    required this.unitNumberType,
    required this.statusOrPublishedField,
  });
}

/// TEMPORARY — see [CurriculumRepository.debugFetchFilteredVsUnfiltered].
class CurriculumRawDebugResult {
  final int filteredCount;
  final int unfilteredCount;
  final List<CurriculumRawDoc> docs;

  const CurriculumRawDebugResult({
    required this.filteredCount,
    required this.unfilteredCount,
    required this.docs,
  });
}

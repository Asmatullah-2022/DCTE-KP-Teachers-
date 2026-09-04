import 'firestore_error_logger.dart';

/// Prefers [remote] emissions; falls back to bundled [local] data if
/// [remote] errors (e.g. rules/indexes not yet deployed, no connectivity).
/// Every fallback is logged so a real misconfiguration is still diagnosable
/// instead of silently hidden.
///
/// By default (`substituteOnEmpty: true`) an empty-but-successful [remote]
/// emission (e.g. Firestore reachable but not yet seeded) is also replaced
/// with [local] — this is right for reference data that's either fully
/// live or fully offline (grades, subjects, the academic calendar). Pass
/// `substituteOnEmpty: false` for a query that legitimately CAN return an
/// empty result while Firestore is perfectly reachable — e.g. curriculum
/// units filtered to only-verified content, where "zero verified yet" is a
/// real, honest state that should show as empty rather than being papered
/// over with unverified bundled data.
Stream<List<T>> withLocalFallback<T>(
  String context,
  Stream<List<T>> remote,
  List<T> local, {
  bool substituteOnEmpty = true,
}) async* {
  try {
    await for (final list in remote) {
      final useLocal = substituteOnEmpty && list.isEmpty;
      yield useLocal ? local : list;
    }
  } catch (e, st) {
    logFirestoreError(context, e, st);
    yield local;
  }
}

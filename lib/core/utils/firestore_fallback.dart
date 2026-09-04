import 'firestore_error_logger.dart';

/// Prefers [remote] emissions; substitutes bundled [local] data for any
/// emission that is empty (e.g. Firestore reachable but not yet seeded),
/// and falls back to [local] entirely if [remote] errors (e.g. rules not
/// yet deployed, no connectivity). Every fallback is logged so a real
/// misconfiguration is still diagnosable instead of silently hidden.
Stream<List<T>> withLocalFallback<T>(
  String context,
  Stream<List<T>> remote,
  List<T> local,
) async* {
  try {
    await for (final list in remote) {
      yield list.isEmpty ? local : list;
    }
  } catch (e, st) {
    logFirestoreError(context, e, st);
    yield local;
  }
}

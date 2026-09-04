import 'dart:developer' as developer;

/// Logs a Firestore stream/query failure with enough context to diagnose it
/// from `adb logcat` (filter on tag "firestore") — e.g. distinguishing
/// permission-denied (rules not deployed / query doesn't match rules) from
/// unavailable (no connectivity) from failed-precondition (missing
/// composite index), which otherwise all collapse into the same generic
/// "source unavailable" UI state.
void logFirestoreError(String context, Object error, [StackTrace? stackTrace]) {
  developer.log(
    'Firestore error in $context: $error',
    name: 'firestore',
    error: error,
    stackTrace: stackTrace,
    level: 1000, // SEVERE
  );
}

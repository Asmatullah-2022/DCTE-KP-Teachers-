// GENERATED PLACEHOLDER — DO NOT commit real values from your own Firebase
// project over this file without keeping it out of public repos, and never
// put Admin/service-account credentials here (this file only carries the
// public, client-safe Firebase config).
//
// Regenerate this file properly with the FlutterFire CLI:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=<your-firebase-project-id>
//
// That command overwrites this file with real values for the platforms you
// select (Android first; iOS/web can be added later without code changes
// elsewhere in the app).

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web — run `flutterfire configure`.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are only configured for Android in this MVP. '
          'Run `flutterfire configure` to add iOS.',
        );
    }
  }

  /// PLACEHOLDER VALUES — replace by running `flutterfire configure`.
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_YOUR_ANDROID_API_KEY',
    appId: 'REPLACE_WITH_YOUR_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
    projectId: 'REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID',
    storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
  );
}

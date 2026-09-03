// Real Android config for the "DCTE KP Teachers" Firebase project,
// extracted from the google-services.json downloaded from the Firebase
// Console (project pk.gov.kp.dcte.dcte_kp_teachers / dcte-kp-teachers-95c33).
// This only carries the public, client-safe Firebase config — never put
// Admin/service-account credentials here.
//
// iOS/web aren't configured — add them later with `flutterfire configure`
// (which will regenerate this file, merging in the new platforms) without
// requiring code changes elsewhere in the app.

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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAxx1fEiU4HQTeJjm1AX846PAznC3tMsjM',
    appId: '1:647312370246:android:29a520097436cf115db847',
    messagingSenderId: '647312370246',
    projectId: 'dcte-kp-teachers-95c33',
    storageBucket: 'dcte-kp-teachers-95c33.firebasestorage.app',
  );
}

// admin/firebase-config.js
// ---------------------------------------------------------------------------
// Copy this file to admin/firebase-config.js and fill in your Firebase
// project's WEB app config (Firebase Console > Project Settings > General
// > "Your apps" > Web app > SDK setup and configuration > Config).
//
// These values are the same kind of public, client-safe config already
// used in lib/config/firebase_options.dart — a Firebase web API key is not
// a secret; access is enforced by Firestore rules + the `admin` custom
// claim, not by hiding this object. Still, admin/firebase-config.js itself
// is gitignored (like the Flutter app's real firebase_options.dart) so you
// don't have to think about it — this .example.js file is the only one
// committed.
export const firebaseConfig = {
  apiKey: 'REPLACE_WITH_YOUR_WEB_API_KEY',
  authDomain: 'REPLACE_WITH_YOUR_PROJECT_ID.firebaseapp.com',
  projectId: 'REPLACE_WITH_YOUR_FIREBASE_PROJECT_ID',
  storageBucket: 'REPLACE_WITH_YOUR_PROJECT_ID.appspot.com',
  messagingSenderId: 'REPLACE_WITH_YOUR_SENDER_ID',
  appId: 'REPLACE_WITH_YOUR_WEB_APP_ID',
};

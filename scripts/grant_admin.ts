#!/usr/bin/env ts-node
/**
 * scripts/grant_admin.ts
 * ---------------------------------------------------------------------------
 * Grants (or revokes) the `admin` custom claim on a Firebase Auth user —
 * the ONLY thing every admin-only Cloud Function in this project checks
 * (see functions/src/admin/adminApi.ts's `requireAdmin`, and
 * firebase/firestore.rules's `isAdmin()`). There is no separate admin
 * password or role table; this claim IS the admin system.
 *
 * WHY THIS IS A SEPARATE SCRIPT, NOT AN APP FEATURE
 * ---------------------------------------------------------------------------
 * Setting a custom claim requires the Firebase Admin SDK, which requires a
 * service-account private key. That key must NEVER be embedded in the
 * Flutter app or committed to the repo (see .gitignore:
 * `serviceAccountKey.json`, `functions/service-account*.json`) — anyone
 * who obtained it could impersonate your entire backend. So granting
 * admin is deliberately a command you run locally with your own
 * credentials, not a button in the app.
 *
 * EXACT STEPS
 * ---------------------------------------------------------------------------
 *   1. Create the Firebase Auth user first if it doesn't exist yet —
 *      easiest via Firebase Console > Authentication > Users > Add user
 *      (email/password is fine), or have them sign in once from the app
 *      (Firebase Auth isn't wired into the UI in this MVP — see
 *      README.md §9 — so for now, create the user directly in the
 *      Console). Copy their UID from that same Users list.
 *
 *   2. Download a service-account key for your Firebase project:
 *      Firebase Console > Project Settings (gear icon) > Service Accounts
 *      tab > "Generate new private key". Save it somewhere OUTSIDE this
 *      repo (e.g. ~/secrets/dcte-service-account.json). NEVER commit it.
 *
 *   3. Run this script:
 *        cd scripts
 *        npm install
 *        GOOGLE_APPLICATION_CREDENTIALS=~/secrets/dcte-service-account.json \
 *          npm run grant:admin -- <uid>
 *
 *      Example:
 *        GOOGLE_APPLICATION_CREDENTIALS=~/secrets/dcte-service-account.json \
 *          npm run grant:admin -- aBcD1234EfGh5678
 *
 *   4. That user must sign out and back in (or refresh their ID token) for
 *      the new claim to take effect — an already-issued ID token doesn't
 *      pick up the claim retroactively. From a Cloud Functions callable,
 *      the client SDK refreshes the token automatically on the next
 *      `getIdToken(true)` / sign-in.
 *
 *   5. To revoke admin later, re-run with --revoke:
 *        npm run grant:admin -- <uid> --revoke
 *
 * WHAT THIS DOES NOT DO
 * ---------------------------------------------------------------------------
 * It does not create a Firestore `users/{uid}` profile document (optional,
 * app-level, unrelated to the security claim) and it does not touch
 * anything in the Flutter app. The claim alone is what every
 * `requireAdmin(request)` check in functions/src/admin/adminApi.ts and
 * every `isAdmin()` check in firebase/firestore.rules actually tests —
 * `request.auth.token.admin === true`.
 */
import { initializeApp, applicationDefault } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

function parseArgs(argv: string[]): { uid: string; revoke: boolean } {
  const positional = argv.filter((a) => !a.startsWith('--'));
  const revoke = argv.includes('--revoke');
  if (positional.length === 0) {
    console.error(
      [
        'Usage: npm run grant:admin -- <uid> [--revoke]',
        '',
        'Find the uid in Firebase Console > Authentication > Users.',
        'See the header comment in scripts/grant_admin.ts for the full walkthrough.',
      ].join('\n'),
    );
    process.exit(1);
  }
  return { uid: positional[0], revoke };
}

async function main() {
  const { uid, revoke } = parseArgs(process.argv.slice(2));

  initializeApp({ credential: applicationDefault() });
  const auth = getAuth();

  const user = await auth.getUser(uid).catch(() => null);
  if (!user) {
    console.error(`No Firebase Auth user found with uid "${uid}". Create the user first (see this script's header comment).`);
    process.exit(1);
  }

  const existingClaims = user.customClaims ?? {};
  await auth.setCustomUserClaims(uid, { ...existingClaims, admin: !revoke });

  console.log(
    revoke
      ? `Revoked admin from uid ${uid} (${user.email ?? 'no email on file'}).`
      : `Granted admin to uid ${uid} (${user.email ?? 'no email on file'}).`,
  );
  console.log('That user must sign out/in (or refresh their ID token) for this to take effect.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

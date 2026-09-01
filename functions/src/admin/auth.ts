import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

/**
 * The entire admin authorization system: every admin-only callable in
 * this project checks exactly this — `request.auth.token.admin === true`,
 * a custom claim set via scripts/grant_admin.ts (never anything embedded
 * in the Flutter app). Firestore rules (`isAdmin()` in
 * firebase/firestore.rules) check the identical claim, so a user's admin
 * status is one single source of truth checked in two places.
 */
export function requireAdmin(request: Pick<CallableRequest, 'auth'>): string {
  const auth = request.auth;
  if (!auth || auth.token?.admin !== true) {
    throw new HttpsError('permission-denied', 'Admin privileges required.');
  }
  return auth.uid;
}

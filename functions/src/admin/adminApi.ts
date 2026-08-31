import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { sendNotificationPush } from '../notifications/sendFcm';

function requireAdmin(request: { auth?: { token?: Record<string, unknown> } }): void {
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError('permission-denied', 'Admin privileges required.');
  }
}

/**
 * List documents awaiting admin review, most recently detected first —
 * the admin-review queue for the DETECTED/DOWNLOADED/EXTRACTED/
 * PENDING_REVIEW states.
 */
export const getPendingDocuments = onCall(async (request) => {
  requireAdmin(request);
  const limit = Math.min(Number(request.data?.limit) || 50, 200);
  const db = getFirestore();
  const snap = await db
    .collection('documents')
    .where('status', 'in', ['detected', 'downloaded', 'extracted', 'pending_review'])
    .orderBy('updatedAt', 'desc')
    .limit(limit)
    .get();
  return {
    documents: snap.docs.map((d) => ({ documentId: d.id, ...d.data() })),
  };
});

/** Approve a pending document: marks it verified. Does NOT publish it. */
export const approveDocument = onCall(async (request) => {
  requireAdmin(request);
  const { documentId, editedMetadata } = request.data ?? {};
  if (!documentId) throw new HttpsError('invalid-argument', 'documentId is required.');

  const db = getFirestore();
  await db
    .collection('documents')
    .doc(documentId)
    .update({
      verified: true,
      status: 'verified',
      ...(editedMetadata ?? {}),
      updatedAt: FieldValue.serverTimestamp(),
    });
  return { ok: true };
});

/** Reject a pending document. */
export const rejectDocument = onCall(async (request) => {
  requireAdmin(request);
  const { documentId, reason } = request.data ?? {};
  if (!documentId) throw new HttpsError('invalid-argument', 'documentId is required.');

  const db = getFirestore();
  await db.collection('documents').doc(documentId).update({
    status: 'rejected',
    verified: false,
    rejectionReason: reason ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/** Publish a verified document as a public notification and push FCM. */
export const publishNotification = onCall(async (request) => {
  requireAdmin(request);
  const { documentId, category, title, titleUrdu, summary, notificationNumber } = request.data ?? {};
  if (!documentId || !category || !title) {
    throw new HttpsError('invalid-argument', 'documentId, category and title are required.');
  }

  const db = getFirestore();
  const docSnap = await db.collection('documents').doc(documentId).get();
  if (!docSnap.exists || docSnap.data()?.verified !== true) {
    throw new HttpsError('failed-precondition', 'Document must be verified before publishing.');
  }

  await db.collection('documents').doc(documentId).update({
    status: 'published',
    updatedAt: FieldValue.serverTimestamp(),
  });

  const notifRef = await db.collection('notifications').add({
    title,
    titleUrdu: titleUrdu ?? null,
    category,
    department: docSnap.data()?.department ?? 'DCTE',
    publishedDate: FieldValue.serverTimestamp(),
    notificationNumber: notificationNumber ?? null,
    description: null,
    summary: summary ?? null,
    sourceUrl: docSnap.data()?.sourceUrl,
    documentId,
    isNew: true,
    isVerified: true,
    searchKeywords: buildKeywords(`${title} ${summary ?? ''}`),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await sendNotificationPush({ notificationId: notifRef.id, title, summary, category });

  return { ok: true, notificationId: notifRef.id };
});

/** Disable/enable a source from the admin panel. */
export const setSourceActive = onCall(async (request) => {
  requireAdmin(request);
  const { sourceId, active } = request.data ?? {};
  if (!sourceId || typeof active !== 'boolean') {
    throw new HttpsError('invalid-argument', 'sourceId and active(boolean) are required.');
  }
  const db = getFirestore();
  await db.collection('sources').doc(sourceId).set({ active }, { merge: true });
  return { ok: true };
});

function buildKeywords(text: string): string[] {
  return Array.from(
    new Set(
      text
        .toLowerCase()
        .replace(/[^a-z0-9؀-ۿ\s]/g, ' ')
        .split(/\s+/)
        .filter((t) => t.length > 1),
    ),
  );
}

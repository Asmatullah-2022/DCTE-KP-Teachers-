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

/**
 * List curriculum rows awaiting review in `curriculum_pending` — the
 * admin-only staging collection every imported/extracted curriculum
 * record lands in until a human confirms it (see
 * scripts/seed/import_seed.ts). Optionally filter by gradeId/subjectId to
 * review one subject at a time instead of scrolling all 1000+ rows.
 */
export const getPendingCurriculum = onCall(async (request) => {
  requireAdmin(request);
  const { gradeId, subjectId, limit } = request.data ?? {};
  const db = getFirestore();
  let query: FirebaseFirestore.Query = db.collection('curriculum_pending');
  if (gradeId) query = query.where('gradeId', '==', gradeId);
  if (subjectId) query = query.where('subjectId', '==', subjectId);
  const snap = await query.limit(Math.min(Number(limit) || 50, 200)).get();
  return {
    records: snap.docs.map((d) => ({ curriculumId: d.id, ...d.data() })),
  };
});

/**
 * Promote one reviewed row from `curriculum_pending` to the public
 * `curriculum` collection the Android app actually queries — the only way
 * a curriculum record ever becomes visible to end users. `editedFields`
 * lets the admin correct anything (e.g. a cleaned-up `unitTitle`) as part
 * of approving it; the record always lands with `needsVerification:
 * false` regardless of what the pending row said, since approving it IS
 * the verification. The pending copy is deleted so the queue only ever
 * shows what's still unreviewed.
 */
export const approveCurriculumRecord = onCall(async (request) => {
  requireAdmin(request);
  const { curriculumId, editedFields } = request.data ?? {};
  if (!curriculumId) throw new HttpsError('invalid-argument', 'curriculumId is required.');

  const db = getFirestore();
  const pendingRef = db.collection('curriculum_pending').doc(curriculumId);
  const pendingSnap = await pendingRef.get();
  if (!pendingSnap.exists) {
    throw new HttpsError('not-found', `No pending curriculum record with id ${curriculumId}.`);
  }

  const data = pendingSnap.data()!;
  await db
    .collection('curriculum')
    .doc(curriculumId)
    .set({
      ...data,
      ...(editedFields ?? {}),
      needsVerification: false,
      searchKeywords: buildKeywords(String((editedFields ?? {}).unitTitle ?? data.unitTitle ?? '')),
      updatedAt: FieldValue.serverTimestamp(),
    });
  await pendingRef.delete();

  return { ok: true };
});

/** Reject a pending curriculum record (e.g. it was mis-parsed garbage) — removes it from the review queue without publishing it. */
export const rejectCurriculumRecord = onCall(async (request) => {
  requireAdmin(request);
  const { curriculumId } = request.data ?? {};
  if (!curriculumId) throw new HttpsError('invalid-argument', 'curriculumId is required.');

  const db = getFirestore();
  await db.collection('curriculum_pending').doc(curriculumId).delete();
  return { ok: true };
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

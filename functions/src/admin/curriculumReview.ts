import { getFirestore, FieldValue, DocumentSnapshot } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { requireAdmin } from './auth';
import { buildKeywords } from './adminApi';

/**
 * Bulk curriculum-review workflow. All of this operates on
 * `curriculum_pending` (admin-only, see firebase/firestore.rules) and the
 * public `curriculum` collection the Android app actually queries.
 *
 * `extractionConfidence` (HIGH/MEDIUM/LOW) and `validation` are computed
 * ONCE, at seed time, by scripts/seed/confidence.ts — every function here
 * only ever READS those fields back from Firestore. This keeps exactly
 * one implementation of the classification rules; duplicating that logic
 * here (a separate npm package from scripts/) would risk the two drifting
 * apart and disagreeing about what's safe to bulk-approve.
 *
 * A record is promoted to the public `curriculum` collection — never
 * deleted from `curriculum_pending`. The pending copy is updated in place
 * (`verificationStatus`, `reviewedBy`, `reviewedAt`) so it remains a
 * permanent, queryable audit trail of every review decision (requirement:
 * "do not delete pending records when approving").
 */

const CHUNK_SIZE = 450; // Firestore batch cap is 500 mutations

async function commitInChunks<T>(items: T[], write: (batch: FirebaseFirestore.WriteBatch, item: T) => void) {
  const db = getFirestore();
  for (let i = 0; i < items.length; i += CHUNK_SIZE) {
    const batch = db.batch();
    for (const item of items.slice(i, i + CHUNK_SIZE)) write(batch, item);
    await batch.commit();
  }
}

interface EditedFields {
  unitTitle?: string;
  unitTitleUrdu?: string | null;
}

/** Builds the two writes (public `curriculum` doc + updated `curriculum_pending` doc) for one approval, without committing. */
export function buildApprovalWrites(
  pendingSnap: DocumentSnapshot,
  reviewerUid: string,
  editedFields: EditedFields | undefined,
): { publicId: string; publicData: FirebaseFirestore.DocumentData; pendingUpdate: FirebaseFirestore.DocumentData } {
  const data = pendingSnap.data()!;
  const now = FieldValue.serverTimestamp();

  const hasEdit = editedFields && (editedFields.unitTitle !== undefined || editedFields.unitTitleUrdu !== undefined);
  const correctionFields = hasEdit
    ? {
        originalExtractedValue: { unitTitle: data.unitTitle, unitTitleUrdu: data.unitTitleUrdu ?? null },
        correctedValue: {
          unitTitle: editedFields!.unitTitle ?? data.unitTitle,
          unitTitleUrdu: editedFields!.unitTitleUrdu ?? data.unitTitleUrdu ?? null,
        },
        correctedBy: reviewerUid,
        correctedAt: now,
      }
    : {};

  const effectiveTitle = hasEdit ? editedFields!.unitTitle ?? data.unitTitle : data.unitTitle;
  const effectiveTitleUrdu = hasEdit ? editedFields!.unitTitleUrdu ?? data.unitTitleUrdu ?? null : data.unitTitleUrdu ?? null;

  const publicData = {
    ...data,
    unitTitle: effectiveTitle,
    unitTitleUrdu: effectiveTitleUrdu,
    needsVerification: false,
    verificationStatus: 'verified',
    reviewedBy: reviewerUid,
    reviewedAt: now,
    ...correctionFields,
    searchKeywords: buildKeywords(effectiveTitle),
    updatedAt: now,
  };

  const pendingUpdate = {
    verificationStatus: 'verified',
    reviewedBy: reviewerUid,
    reviewedAt: now,
    ...correctionFields,
    updatedAt: now,
  };

  return { publicId: pendingSnap.id, publicData, pendingUpdate };
}

/**
 * List curriculum rows awaiting review in `curriculum_pending`. Filter by
 * any combination of gradeId/subjectId/semester/confidence/verificationStatus
 * to work through the review queue in manageable, human-sized batches
 * (e.g. one grade+subject+semester group at a time) instead of scrolling
 * all 1000+ rows — this is the query the admin dashboard's grouped tree
 * view (Grade -> Subject -> Semester) is built on.
 */
export const getPendingCurriculum = onCall(async (request) => {
  requireAdmin(request);
  const { gradeId, subjectId, semester, confidence, verificationStatus, limit } = request.data ?? {};
  const db = getFirestore();
  let query: FirebaseFirestore.Query = db.collection('curriculum_pending');
  if (gradeId) query = query.where('gradeId', '==', gradeId);
  if (subjectId) query = query.where('subjectId', '==', subjectId);
  if (semester) query = query.where('semester', '==', semester);
  if (confidence) query = query.where('extractionConfidence', '==', confidence);
  if (verificationStatus) query = query.where('verificationStatus', '==', verificationStatus);
  const snap = await query.limit(Math.min(Number(limit) || 500, 2000)).get();
  return {
    records: snap.docs.map((d) => ({ curriculumId: d.id, ...d.data() })),
  };
});

/**
 * Promote ONE reviewed row to the public `curriculum` collection — the
 * only way a curriculum record ever becomes visible to end users.
 * `editedFields` lets the admin correct the title as part of approving it
 * (recorded in `correctedValue`/`originalExtractedValue`, never
 * overwriting the immutable `unitTitle`/`rawText`/`extractedText` fields
 * captured at import time). Works on a record of ANY confidence level —
 * this is the single-record path; see `bulkApproveHighConfidence` /
 * `approveSelectedCurriculum` for batch approval, which only ever touches
 * HIGH-confidence records automatically.
 */
export const approveCurriculumRecord = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { curriculumId, editedFields } = request.data ?? {};
  if (!curriculumId) throw new HttpsError('invalid-argument', 'curriculumId is required.');

  const db = getFirestore();
  const pendingRef = db.collection('curriculum_pending').doc(curriculumId);
  const pendingSnap = await pendingRef.get();
  if (!pendingSnap.exists) {
    throw new HttpsError('not-found', `No pending curriculum record with id ${curriculumId}.`);
  }

  const { publicId, publicData, pendingUpdate } = buildApprovalWrites(pendingSnap, uid, editedFields);
  await db.collection('curriculum').doc(publicId).set(publicData);
  await pendingRef.update(pendingUpdate);

  return { ok: true };
});

/** Edit a pending record's title WITHOUT approving or rejecting it — lets an admin fix text first, decide later. */
export const editCurriculumPending = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { curriculumId, correctedValue } = request.data ?? {};
  if (!curriculumId) throw new HttpsError('invalid-argument', 'curriculumId is required.');
  if (!correctedValue || (correctedValue.unitTitle === undefined && correctedValue.unitTitleUrdu === undefined)) {
    throw new HttpsError('invalid-argument', 'correctedValue.unitTitle and/or correctedValue.unitTitleUrdu is required.');
  }

  const db = getFirestore();
  const ref = db.collection('curriculum_pending').doc(curriculumId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', `No pending curriculum record with id ${curriculumId}.`);
  const data = snap.data()!;

  await ref.update({
    originalExtractedValue: { unitTitle: data.unitTitle, unitTitleUrdu: data.unitTitleUrdu ?? null },
    correctedValue: {
      unitTitle: correctedValue.unitTitle ?? data.unitTitle,
      unitTitleUrdu: correctedValue.unitTitleUrdu ?? data.unitTitleUrdu ?? null,
    },
    correctedBy: uid,
    correctedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true };
});

/** Reject a pending curriculum record (e.g. it's mis-parsed garbage) — marks it rejected, never published, never deleted. */
export const rejectCurriculumRecord = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { curriculumId, reason } = request.data ?? {};
  if (!curriculumId) throw new HttpsError('invalid-argument', 'curriculumId is required.');

  const db = getFirestore();
  await db.collection('curriculum_pending').doc(curriculumId).update({
    verificationStatus: 'rejected',
    reviewedBy: uid,
    reviewedAt: FieldValue.serverTimestamp(),
    rejectionReason: reason ?? null,
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/** Approve a specific, admin-picked list of records (the dashboard's "Approve Selected" button). Any confidence level. */
export const approveSelectedCurriculum = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { curriculumIds } = request.data ?? {};
  if (!Array.isArray(curriculumIds) || curriculumIds.length === 0) {
    throw new HttpsError('invalid-argument', 'curriculumIds (non-empty array) is required.');
  }
  if (curriculumIds.length > 2000) {
    throw new HttpsError('invalid-argument', 'Too many curriculumIds in one call (max 2000).');
  }

  const db = getFirestore();
  const writes: Array<{ publicId: string; publicData: FirebaseFirestore.DocumentData; pendingUpdate: FirebaseFirestore.DocumentData }> = [];
  const notFound: string[] = [];

  for (const id of curriculumIds as string[]) {
    const snap = await db.collection('curriculum_pending').doc(id).get();
    if (!snap.exists) {
      notFound.push(id);
      continue;
    }
    writes.push(buildApprovalWrites(snap, uid, undefined));
  }

  await commitInChunks(writes, (batch, w) => {
    batch.set(db.collection('curriculum').doc(w.publicId), w.publicData);
    batch.update(db.collection('curriculum_pending').doc(w.publicId), w.pendingUpdate);
  });

  return { ok: true, approved: writes.length, notFound };
});

/** Reject a specific, admin-picked list of records (the dashboard's "Reject Selected" button). */
export const rejectSelectedCurriculum = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { curriculumIds, reason } = request.data ?? {};
  if (!Array.isArray(curriculumIds) || curriculumIds.length === 0) {
    throw new HttpsError('invalid-argument', 'curriculumIds (non-empty array) is required.');
  }

  const db = getFirestore();
  await commitInChunks(curriculumIds as string[], (batch, id) =>
    batch.update(db.collection('curriculum_pending').doc(id), {
      verificationStatus: 'rejected',
      reviewedBy: uid,
      reviewedAt: FieldValue.serverTimestamp(),
      rejectionReason: reason ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    }),
  );

  return { ok: true, rejected: curriculumIds.length };
});

/**
 * The ONE bulk-automation entry point: approves every `curriculum_pending`
 * record that is BOTH `extractionConfidence: 'HIGH'` AND still
 * `verificationStatus: 'pending_review'` (never touches MEDIUM or LOW —
 * those always require a human to open and read them individually, per
 * the project's own "never auto-approve LOW/be conservative with Urdu"
 * rule, since MEDIUM is always Urdu-containing and LOW always failed
 * validation or looks OCR-scrambled — see scripts/seed/confidence.ts).
 * Optionally scoped to one grade/subject/semester. `dryRun: true` returns
 * the count and list that WOULD be approved without writing anything, so
 * an admin can sanity-check a batch before committing to it.
 */
export const bulkApproveHighConfidence = onCall(async (request) => {
  const uid = requireAdmin(request);
  const { gradeId, subjectId, semester, dryRun } = request.data ?? {};

  const db = getFirestore();
  let query: FirebaseFirestore.Query = db
    .collection('curriculum_pending')
    .where('extractionConfidence', '==', 'HIGH')
    .where('verificationStatus', '==', 'pending_review');
  if (gradeId) query = query.where('gradeId', '==', gradeId);
  if (subjectId) query = query.where('subjectId', '==', subjectId);
  if (semester) query = query.where('semester', '==', semester);

  const snap = await query.limit(2000).get();

  if (dryRun) {
    return {
      ok: true,
      dryRun: true,
      wouldApprove: snap.size,
      curriculumIds: snap.docs.map((d) => d.id),
    };
  }

  const writes = snap.docs.map((d) => buildApprovalWrites(d, uid, undefined));
  await commitInChunks(writes, (batch, w) => {
    batch.set(db.collection('curriculum').doc(w.publicId), w.publicData);
    batch.update(db.collection('curriculum_pending').doc(w.publicId), w.pendingUpdate);
  });

  return { ok: true, dryRun: false, approved: writes.length };
});

/**
 * Dashboard summary counts (requirement: total/high/medium/low/verified/
 * pending/rejected). Uses Firestore's server-side `count()` aggregation so
 * this stays cheap even with 1000+ pending records — no document bodies
 * are read.
 */
export const getCurriculumReviewSummary = onCall(async (request) => {
  requireAdmin(request);
  const db = getFirestore();
  const col = db.collection('curriculum_pending');

  const [total, high, medium, low, verified, pending, rejected, publicTotal] = await Promise.all([
    col.count().get(),
    col.where('extractionConfidence', '==', 'HIGH').count().get(),
    col.where('extractionConfidence', '==', 'MEDIUM').count().get(),
    col.where('extractionConfidence', '==', 'LOW').count().get(),
    col.where('verificationStatus', '==', 'verified').count().get(),
    col.where('verificationStatus', '==', 'pending_review').count().get(),
    col.where('verificationStatus', '==', 'rejected').count().get(),
    db.collection('curriculum').count().get(),
  ]);

  return {
    totalExtracted: total.data().count,
    highConfidence: high.data().count,
    mediumConfidence: medium.data().count,
    lowConfidence: low.data().count,
    verified: verified.data().count,
    pending: pending.data().count,
    rejected: rejected.data().count,
    publishedToApp: publicTotal.data().count,
  };
});

/**
 * Structured review report for the dashboard's "Export Review Report"
 * button — grouped by grade -> subject -> semester with confidence and
 * status breakdowns per group, plus the full list of records that failed
 * hard validation (missing fields, duplicates) so those can be triaged
 * first. The dashboard downloads this as a JSON file client-side.
 */
export const exportCurriculumReviewReport = onCall(async (request) => {
  requireAdmin(request);
  const db = getFirestore();
  const snap = await db.collection('curriculum_pending').get();

  type GroupStats = {
    total: number;
    high: number;
    medium: number;
    low: number;
    verified: number;
    pending: number;
    rejected: number;
  };
  const groups = new Map<string, GroupStats>();
  const validationFailures: Array<{ curriculumId: string; issues: string[] }> = [];

  const blank = (): GroupStats => ({ total: 0, high: 0, medium: 0, low: 0, verified: 0, pending: 0, rejected: 0 });

  for (const doc of snap.docs) {
    const d = doc.data();
    const key = `${d.gradeId} > ${d.subjectId} > ${d.semester}`;
    const g = groups.get(key) ?? blank();
    g.total++;
    if (d.extractionConfidence === 'HIGH') g.high++;
    else if (d.extractionConfidence === 'MEDIUM') g.medium++;
    else g.low++;
    if (d.verificationStatus === 'verified') g.verified++;
    else if (d.verificationStatus === 'rejected') g.rejected++;
    else g.pending++;
    groups.set(key, g);

    if (d.validation && d.validation.passed === false) {
      validationFailures.push({ curriculumId: doc.id, issues: d.validation.issues ?? [] });
    }
  }

  return {
    generatedAt: new Date().toISOString(),
    totalRecords: snap.size,
    groups: Array.from(groups.entries()).map(([group, stats]) => ({ group, ...stats })),
    validationFailures,
  };
});

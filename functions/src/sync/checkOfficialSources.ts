import { getFirestore, FieldValue, DocumentReference, Timestamp } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { SOURCE_CONFIGS, SourceConfig } from '../sources/sourceConfig';
import { politeFetch, checkRobotsAllowed } from '../utils/http';
import { extractLinks } from '../parsers/htmlParser';
import { extractPdfText, extractCurriculumCandidates } from '../parsers/pdfParser';
import { classifyCategory, parseLooseDate } from '../parsers/classify';
import { sha256 } from '../utils/hash';
import { startSyncLog, SyncCounts } from './syncLogger';

/**
 * DOCUMENT PIPELINE
 *
 *   DETECTED -> DOWNLOADED -> EXTRACTED -> PENDING_REVIEW -> VERIFIED ->
 *   PUBLISHED -> FCM NOTIFICATION
 *
 * This function drives a `documents` row through DETECTED, DOWNLOADED (for
 * PDFs), EXTRACTED (raw text + a curriculum-candidate count, PDFs only),
 * and lands it at PENDING_REVIEW. VERIFIED/PUBLISHED and the FCM
 * notification only ever happen behind an explicit admin action — see
 * `admin/adminApi.ts` (`approveDocument`, `publishNotification`) — so
 * nothing auto-detected or AI-extracted is ever shown to end users without
 * a human sign-off. Structured `curriculum` records are never created by
 * this function; that stays a deliberate, reviewed step via
 * `scripts/import_dcte_pdf.ts` (see that file's header for why).
 */
async function syncOneSource(config: SourceConfig): Promise<void> {
  const db = getFirestore();
  const log = await startSyncLog(config.sourceId);
  const counts: SyncCounts = { documentsFound: 0, documentsAdded: 0, documentsUpdated: 0, documentsSkipped: 0 };
  const errors: string[] = [];

  if (config.verificationStatus === 'NEEDS_LIVE_VERIFICATION') {
    errors.push(
      `Source "${config.sourceId}" selectors are marked NEEDS_LIVE_VERIFICATION ` +
        `(see functions/src/sources/sourceConfig.ts) — results from this run should ` +
        `be treated as unverified until the selectors are confirmed against the live site.`,
    );
  }

  try {
    const allowed = await checkRobotsAllowed(config.baseUrl, new URL(config.listUrl).pathname);
    if (!allowed) {
      errors.push(`robots.txt disallows crawling ${config.listUrl}; skipping.`);
      await log.finish('failed', counts, errors);
      await db.collection('sources').doc(config.sourceId).update({
        lastCheckedAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    const res = await politeFetch(config.listUrl);
    const html = await res.text();
    const links = extractLinks(html, config);
    counts.documentsFound = links.length;

    if (links.length === 0) {
      errors.push(
        `No links matched selector "${config.linkSelector}" on ${config.listUrl}. ` +
          `The site markup may differ from sources/sourceConfig.ts defaults — verify selectors.`,
      );
    }

    for (const link of links) {
      try {
        const existingSnap = await db
          .collection('documents')
          .where('sourceUrl', '==', link.url)
          .limit(1)
          .get();

        if (existingSnap.empty) {
          // DETECTED
          const guessedDate = parseLooseDate(link.publishedDateGuess);
          const docRef = await db.collection('documents').add({
            title: link.title,
            titleUrdu: null,
            documentType: link.isPdf ? 'Notification' : 'Webpage',
            department: config.department,
            category: classifyCategory(link.title),
            publishedDate: guessedDate ? Timestamp.fromDate(guessedDate) : null,
            notificationNumber: null,
            sourceUrl: link.url,
            // documentUrl mirrors sourceUrl for a link that's already a
            // direct file (the common case for this source's selector).
            // If a future source instead links to an announcement PAGE
            // that embeds the actual PDF elsewhere, documentUrl stays
            // null until a page-level fetch to resolve the real file link
            // is added — not yet implemented, so it's left honestly null
            // rather than guessed.
            documentUrl: link.isPdf ? link.url : null,
            storageUrl: null,
            fileHash: null,
            fileSize: null,
            pageCount: null,
            summary: null,
            aiSummary: null,
            rawExtractionPreview: null,
            curriculumCandidateCount: null,
            status: 'detected',
            verified: false,
            searchKeywords: buildKeywords(link.title),
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });

          if (link.isPdf) {
            await downloadAndExtractPdf(docRef, link.url, errors);
          } else {
            // Non-PDF (webpage) links have nothing to download/extract —
            // they go straight to PENDING_REVIEW for an admin to look at.
            await docRef.update({ status: 'pending_review', updatedAt: FieldValue.serverTimestamp() });
          }
          counts.documentsAdded++;
        } else if (link.isPdf) {
          const existingDoc = existingSnap.docs[0];
          const existingHash = existingDoc.data().fileHash as string | undefined;
          try {
            const pdfRes = await politeFetch(link.url, { maxRetries: 1 });
            const buffer = Buffer.from(await pdfRes.arrayBuffer());
            const newHash = sha256(buffer);
            if (existingHash && newHash !== existingHash) {
              // Changed document: re-run DOWNLOADED -> EXTRACTED -> PENDING_REVIEW.
              await existingDoc.ref.update({
                status: 'downloaded',
                fileHash: newHash,
                fileSize: buffer.byteLength,
                verified: false,
                updatedAt: FieldValue.serverTimestamp(),
              });
              await extractPdfIntoDocument(existingDoc.ref, buffer, errors);
              counts.documentsUpdated++;
            } else {
              counts.documentsSkipped++;
            }
          } catch (pdfErr) {
            errors.push(`Failed to re-check PDF hash for ${link.url}: ${(pdfErr as Error).message}`);
            counts.documentsSkipped++;
          }
        } else {
          counts.documentsSkipped++;
        }
      } catch (linkErr) {
        errors.push(`Error processing ${link.url}: ${(linkErr as Error).message}`);
      }
    }

    await db.collection('sources').doc(config.sourceId).set(
      {
        name: config.name,
        baseUrl: config.baseUrl,
        sourceType: 'html',
        active: true,
        checkFrequency: 'daily',
        verificationStatus: config.verificationStatus,
        lastCheckedAt: FieldValue.serverTimestamp(),
        lastSuccessfulCheckAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    await log.finish(errors.length > 0 ? 'partial' : 'success', counts, errors);
  } catch (err) {
    errors.push((err as Error).message);
    await log.finish('failed', counts, errors);
    await db.collection('sources').doc(config.sourceId).set(
      { lastCheckedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
    logger.error(`Sync failed for ${config.sourceId}`, err);
  }
}

/** DOWNLOADED -> EXTRACTED -> PENDING_REVIEW for a newly detected PDF. */
async function downloadAndExtractPdf(
  docRef: DocumentReference,
  url: string,
  errors: string[],
): Promise<void> {
  try {
    const pdfRes = await politeFetch(url, { maxRetries: 1 });
    const buffer = Buffer.from(await pdfRes.arrayBuffer());
    const fileHash = sha256(buffer);
    await docRef.update({
      status: 'downloaded',
      fileHash,
      fileSize: buffer.byteLength,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await extractPdfIntoDocument(docRef, buffer, errors);
  } catch (pdfErr) {
    errors.push(`Failed to download PDF ${url}: ${(pdfErr as Error).message}`);
    // Stays at DETECTED with no hash — an admin can still see and manually
    // fetch it; the next scheduled run will retry the download.
  }
}

/**
 * EXTRACTED -> PENDING_REVIEW. Runs pdf-parse + the conservative curriculum
 * candidate detector so an admin has a preview and a candidate count before
 * deciding to run the full importer (scripts/import_dcte_pdf.ts) — this
 * never writes to the `curriculum` collection itself.
 */
async function extractPdfIntoDocument(
  docRef: DocumentReference,
  buffer: Buffer,
  errors: string[],
): Promise<void> {
  try {
    const { rawText, pageCount } = await extractPdfText(buffer);
    const candidates = extractCurriculumCandidates(rawText);
    await docRef.update({
      status: 'extracted',
      pageCount,
      rawExtractionPreview: rawText.slice(0, 2000),
      curriculumCandidateCount: candidates.length,
      updatedAt: FieldValue.serverTimestamp(),
    });
    await docRef.update({ status: 'pending_review', updatedAt: FieldValue.serverTimestamp() });
  } catch (extractErr) {
    errors.push(`PDF text extraction failed: ${(extractErr as Error).message}`);
    // Still surface it for manual review even if extraction failed.
    await docRef.update({ status: 'pending_review', updatedAt: FieldValue.serverTimestamp() });
  }
}

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

/** Runs once daily, Asia/Karachi. Checks all active sources. */
export const checkOfficialSources = onSchedule(
  { schedule: '0 6 * * *', timeZone: 'Asia/Karachi', retryCount: 2, memory: '512MiB' },
  async () => {
    for (const config of SOURCE_CONFIGS) {
      await syncOneSource(config);
    }
  },
);

/** Admin-triggered manual re-sync of a single source (see admin panel). */
export const forceSyncSource = onCall(async (request) => {
  if (request.auth?.token?.admin !== true) {
    throw new HttpsError('permission-denied', 'Admin privileges required.');
  }
  const sourceId = request.data?.sourceId as string | undefined;
  const config = SOURCE_CONFIGS.find((c) => c.sourceId === sourceId);
  if (!config) {
    throw new HttpsError('not-found', `Unknown sourceId: ${sourceId}`);
  }
  await syncOneSource(config);
  return { ok: true };
});

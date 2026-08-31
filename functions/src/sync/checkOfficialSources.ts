import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { SOURCE_CONFIGS, SourceConfig } from '../sources/sourceConfig';
import { politeFetch, checkRobotsAllowed } from '../utils/http';
import { extractLinks } from '../parsers/htmlParser';
import { sha256 } from '../utils/hash';
import { startSyncLog, SyncCounts } from './syncLogger';

/**
 * DOCUMENT PIPELINE
 * DETECTED -> DOWNLOADED -> TEXT/PDF EXTRACTION -> METADATA EXTRACTION ->
 * RELEVANCE CLASSIFICATION -> PENDING REVIEW -> VERIFIED -> PUBLISHED -> FCM
 *
 * This function implements DETECTED through PENDING REVIEW automatically.
 * VERIFIED/PUBLISHED and the FCM notification are gated behind an explicit
 * admin action (see admin/adminApi.ts `approveDocument` /
 * `publishNotification`) — nothing auto-extracted is ever shown to end
 * users without human sign-off.
 */
async function syncOneSource(config: SourceConfig): Promise<void> {
  const db = getFirestore();
  const log = await startSyncLog(config.sourceId);
  const counts: SyncCounts = { documentsFound: 0, documentsAdded: 0, documentsUpdated: 0, documentsSkipped: 0 };
  const errors: string[] = [];

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
          let fileHash: string | undefined;
          let fileSize: number | undefined;

          if (link.isPdf) {
            try {
              const pdfRes = await politeFetch(link.url, { maxRetries: 1 });
              const buffer = Buffer.from(await pdfRes.arrayBuffer());
              fileHash = sha256(buffer);
              fileSize = buffer.byteLength;
            } catch (pdfErr) {
              errors.push(`Failed to download PDF ${link.url}: ${(pdfErr as Error).message}`);
            }
          }

          await db.collection('documents').add({
            title: link.title,
            titleUrdu: null,
            documentType: link.isPdf ? 'Notification' : 'Webpage',
            department: config.department,
            publishedDate: null,
            notificationNumber: null,
            sourceUrl: link.url,
            storageUrl: null,
            fileHash: fileHash ?? null,
            fileSize: fileSize ?? null,
            pageCount: null,
            summary: null,
            aiSummary: null,
            status: 'pending_review',
            verified: false,
            searchKeywords: buildKeywords(link.title),
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          });
          counts.documentsAdded++;
        } else if (link.isPdf) {
          const existingDoc = existingSnap.docs[0];
          const existingHash = existingDoc.data().fileHash as string | undefined;
          try {
            const pdfRes = await politeFetch(link.url, { maxRetries: 1 });
            const buffer = Buffer.from(await pdfRes.arrayBuffer());
            const newHash = sha256(buffer);
            if (existingHash && newHash !== existingHash) {
              await existingDoc.ref.update({
                fileHash: newHash,
                fileSize: buffer.byteLength,
                status: 'pending_review',
                verified: false,
                updatedAt: FieldValue.serverTimestamp(),
              });
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

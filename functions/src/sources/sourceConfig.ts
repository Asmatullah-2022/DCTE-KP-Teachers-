/**
 * Configurable per-source selectors for HTML monitoring.
 *
 * NEEDS_LIVE_VERIFICATION
 * ------------------------
 * Every `linkSelector` / `titleSelector` / `dateSelector` below is tagged
 * `verificationStatus: 'NEEDS_LIVE_VERIFICATION'`. This build's network
 * egress to dcte.kpese.gov.pk and kpese.gov.pk is blocked by the sandbox's
 * proxy (confirmed via both WebFetch and a direct `curl`, which returned
 * `CONNECT tunnel failed, response 403` for the domain) — so the live DOM
 * was never inspected. The selectors below are conservative, best-effort
 * defaults for a typical WordPress site (both domains run WordPress), NOT
 * confirmed against the real markup. Do not treat a `NEEDS_LIVE_VERIFICATION`
 * source as production-ready.
 *
 * Before relying on automated sync in production:
 *   1. Open each `listUrl` in a browser, inspect the notification/document
 *      list markup (view-source or devtools), and update `linkSelector` /
 *      `titleSelector` / `dateSelector` to match what you actually see.
 *   2. Flip that source's `verificationStatus` to `'VERIFIED'` once you've
 *      confirmed it (this is a code-level flag here; the matching
 *      Firestore `sources/{sourceId}` doc also carries a `verified`
 *      boolean the admin panel can toggle — see admin/adminApi.ts
 *      `setSourceActive`).
 *   3. Run `cd functions && npm run shell` and call `forceSyncSource({
 *      sourceId })` against it to confirm it discovers the expected links
 *      (check the resulting `sync_logs` document for `documentsFound`).
 *   4. Until verified, treat anything the scheduled function detects as
 *      unreliable and prefer the manual importer
 *      (`scripts/import_dcte_pdf.ts`) / admin manual entry — never publish
 *      an auto-detected item without a human reviewing it first (see the
 *      DETECTED → DOWNLOADED → EXTRACTED → PENDING_REVIEW → VERIFIED →
 *      PUBLISHED → FCM pipeline documented in sync/checkOfficialSources.ts).
 */
export type SelectorVerificationStatus = 'NEEDS_LIVE_VERIFICATION' | 'VERIFIED';

export interface SourceConfig {
  sourceId: string;
  name: string;
  baseUrl: string;
  listUrl: string;
  department: 'DCTE' | 'KPESE';
  /** CSS selector (cheerio) matching anchor tags for notifications/documents. */
  linkSelector: string;
  /** Optional selector for a title element relative to each link. */
  titleSelector?: string;
  /** Optional selector for a date element relative to each link's container. */
  dateSelector?: string;
  /**
   * Whether `linkSelector`/`titleSelector`/`dateSelector` have been checked
   * against the live site. Always `'NEEDS_LIVE_VERIFICATION'` out of the
   * box — see the module doc comment above.
   */
  verificationStatus: SelectorVerificationStatus;
}

export const SOURCE_CONFIGS: SourceConfig[] = [
  {
    sourceId: 'dcte_kpese',
    name: 'DCTE, Khyber Pakhtunkhwa',
    baseUrl: 'https://dcte.kpese.gov.pk/',
    listUrl: 'https://dcte.kpese.gov.pk/',
    department: 'DCTE',
    // Default WordPress pattern: links to uploaded PDFs and post pages.
    linkSelector: 'a[href$=".pdf"], article a[href]',
    titleSelector: undefined,
    dateSelector: 'time, .entry-date, .post-date',
    verificationStatus: 'NEEDS_LIVE_VERIFICATION',
  },
  {
    sourceId: 'kpese_notifications',
    name: 'KPESE Notifications',
    baseUrl: 'https://kpese.gov.pk/',
    listUrl: 'https://kpese.gov.pk/category/notifications/',
    department: 'KPESE',
    linkSelector: 'article a[href], .post a[href]',
    titleSelector: '.entry-title, h2, h3',
    dateSelector: 'time, .entry-date, .post-date',
    verificationStatus: 'NEEDS_LIVE_VERIFICATION',
  },
];

/** The official semester-wise curriculum PDF — the app's seed source document. */
export const DCTE_SEMESTER_NOTIFICATION_PDF_URL =
  'https://dcte.kpese.gov.pk/wp-content/uploads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf';

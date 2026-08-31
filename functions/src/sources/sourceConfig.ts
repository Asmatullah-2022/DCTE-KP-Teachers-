/**
 * Configurable per-source selectors for HTML monitoring.
 *
 * IMPORTANT: This environment could not reach dcte.kpese.gov.pk or
 * kpese.gov.pk to inspect live markup (outbound access was blocked), so the
 * selectors below are best-effort, conservative defaults for a typical
 * WordPress site (both domains are WordPress-based government sites), NOT
 * verified against the live DOM. Before relying on automated sync in
 * production:
 *   1. Open each source URL in a browser, inspect the notification/document
 *      list markup, and update `linkSelector` / `dateSelector` accordingly.
 *   2. Run `npm run shell` and call `forceSyncSource` against one source to
 *      confirm it finds the expected links.
 *   3. Until verified, use the admin panel's manual import to add documents
 *      — never publish auto-detected items without review (see
 *      DOCUMENT_PIPELINE in sync/checkOfficialSources.ts).
 */
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
  },
];

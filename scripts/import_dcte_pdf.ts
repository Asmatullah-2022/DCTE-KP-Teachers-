#!/usr/bin/env ts-node
/**
 * scripts/import_dcte_pdf.ts
 * ---------------------------------------------------------------------------
 * Real importer for the official DCTE semester-wise curriculum notification:
 *
 *   https://dcte.kpese.gov.pk/wp-content/uploads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf
 *
 * WHY THIS RUNS LOCALLY, NOT IN THIS SANDBOX
 * ---------------------------------------------------------------------------
 * This development environment's outbound network access to
 * dcte.kpese.gov.pk is blocked by its proxy (confirmed via both an agent
 * WebFetch call and a direct `curl`, which returned
 * "CONNECT tunnel failed, response 403"). It cannot download the PDF from
 * the live site. It HAS, however, been run against the real official PDF
 * once the user uploaded it directly into the session — see "TESTED
 * AGAINST THE REAL PDF" below. Run this again yourself whenever the
 * notification is revised, against a freshly downloaded copy.
 *
 * HOW TO GET THE PDF TO THIS SCRIPT
 * ---------------------------------------------------------------------------
 *   1. Open the URL above in a normal browser and save the PDF, e.g. to
 *      ~/Downloads/dcte-semester-notification.pdf
 *   2. From the repo root:
 *        cd scripts
 *        npm install
 *        npm run import:pdf -- ~/Downloads/dcte-semester-notification.pdf
 *   3. Review the console summary and the generated
 *      seed/subjects.json / seed/curriculum.json — every row is written
 *      with needsVerification=true (see below) until a human confirms it.
 *   4. Import into Firestore: `npm run seed` (see scripts/seed/import_seed.ts).
 *
 * THE TABLE LAYOUT THIS PARSER TARGETS
 * ---------------------------------------------------------------------------
 * The real notification is a 24-page table, one block per subject per
 * grade: a narrow left "S.No / Subject (Session ...)" column, then a
 * "Semester I" units column and a "Semester II" units column side by side,
 * each an independently numbered list ("1. Title", "2. Title", ...; the
 * numbering is often literally continuous across both columns, e.g.
 * Semester I runs 1-32 and Semester II continues 33-68 for the same
 * subject — this script preserves whatever number is printed rather than
 * renumbering, per the "preserve official source terminology" rule). A
 * pdfjs text item carries no explicit "this is column 2" flag, so this
 * parser buckets every text item on a page by its X coordinate: a fixed
 * threshold (see LABEL_MAX_X below) separates the narrow label column,
 * measured directly from the real PDF's "S.NO/SUBJECT" header cell — but
 * the Semester-I/Semester-II boundary itself is NOT fixed (it was observed
 * to shift a few points from block to block), so that split is adaptive —
 * see `splitUnitColumns`'s doc comment. Items are first clustered into
 * visual rows by Y-proximity (glyphs on the same printed line can differ
 * in Y by a couple of points due to font metrics — see ROW_Y_TOLERANCE), then split into
 * label/Semester-I/Semester-II columns by X.
 *
 * A few subjects (regional-language primers in ECE and Grade 1: Hindko,
 * Pashto, Seraiki, Khowar) don't enumerate individual unit titles at all —
 * the notification just gives a page range ("Page No. 01 to 18") or lesson
 * range ("سبق 1 تا 9" / "صفحہ نمبر ..."). This parser recognizes that and
 * stores it as a single scope-note record per semester rather than
 * inventing per-lesson titles that don't exist in the source.
 *
 * URDU/ARABIC-SCRIPT TEXT — WHAT IS AND ISN'T ATTEMPTED
 * ---------------------------------------------------------------------------
 * Arabic-script glyphs in this PDF are positioned right-to-left, and
 * diacritic marks (harakat/tashkeel) are often separate glyphs offset
 * slightly in Y from their base letter. Correctly reconstructing Urdu
 * reading order from raw glyph positions is a hard, error-prone problem
 * (bidi + Arabic presentation-form reshaping), and this script does NOT
 * attempt it — sorting glyphs by X ascending (the same left-to-right rule
 * used for English/Latin text) can visibly scramble Urdu word order. Per
 * the project's explicit accuracy rule ("never invent, never silently
 * guess"), every row containing Arabic-script text is preserved EXACTLY
 * as pdfjs extracted it (raw glyph order, uncorrected) in both
 * `unitTitle` and `unitTitleUrdu`, and is always written with
 * `needsVerification: true`. Treat the Urdu text in curriculum.json as a
 * pointer to the right sourcePage, not as a trustworthy transcription —
 * an admin must read it from the PDF directly (or re-key it) before it is
 * ever shown as verified.
 *
 * If the PDF contains no extractable text at all (i.e. it is a scanned
 * image rather than a text-layer PDF), this script will say so plainly and
 * write nothing — see "NO EXTRACTABLE TEXT" below for what to do next.
 *
 * If a real DCTE/KPESE PDF uses different wording/layout than expected,
 * pass `--debug` to print the raw per-row, per-column text this script
 * reconstructed BEFORE any pattern matching runs, so you can see exactly
 * what it saw and adjust the constants/regexes below accordingly.
 * `--dry-run` combined with `--debug` is the fastest way to iterate
 * without writing files each time.
 *
 * TESTED AGAINST THE REAL PDF
 * ---------------------------------------------------------------------------
 * This parser was built and iterated directly against the actual official
 * 24-page "Revised Notification Semester-wise Course Grade I-VIII" PDF
 * (Session 2025-26), uploaded by the project owner, using --debug output
 * from real pages spanning ECE through Grade 8 (including regional
 * languages, Nazira-e-Quran, and math/science/social-studies-style
 * numbered-list subjects) to calibrate the column thresholds and
 * row-clustering tolerance below. It is not a synthetic fixture.
 */
import * as fs from 'fs';
import * as path from 'path';
import { createHash } from 'crypto';

// eslint-disable-next-line @typescript-eslint/no-var-requires
const pdfParse = require('pdf-parse');

const DEFAULT_SOURCE_URL =
  'https://dcte.kpese.gov.pk/wp-content/uploads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf';

interface CliArgs {
  pdfPath: string;
  outDir: string;
  sourceUrl: string;
  session: string | null;
  dryRun: boolean;
  debug: boolean;
}

function parseArgs(argv: string[]): CliArgs {
  const positional = argv.filter((a) => !a.startsWith('--'));
  const flags = new Map<string, string>();
  for (const a of argv) {
    if (a.startsWith('--')) {
      const [k, v] = a.slice(2).split('=');
      flags.set(k, v ?? 'true');
    }
  }
  if (positional.length === 0) {
    console.error(
      [
        'Usage: npm run import:pdf -- <path-to-dcte-semester-notification.pdf> [--session=2025-26] [--source-url=...] [--dry-run] [--debug]',
        '',
        'Example:',
        '  npm run import:pdf -- ~/Downloads/dcte-semester-notification.pdf',
        '',
        'See the header comment in scripts/import_dcte_pdf.ts for how to obtain the PDF.',
      ].join('\n'),
    );
    process.exit(1);
  }
  return {
    pdfPath: positional[0],
    outDir: flags.get('out-dir') ?? path.join(__dirname, 'seed'),
    sourceUrl: flags.get('source-url') ?? DEFAULT_SOURCE_URL,
    session: flags.get('session') ?? null,
    dryRun: flags.has('dry-run'),
    debug: flags.has('debug'),
  };
}

// --- PDF text extraction: rows + X-based columns ---------------------------

interface Item {
  x: number;
  y: number;
  str: string;
}

interface Row {
  y: number;
  items: Item[]; // sorted by x ascending
}

interface PageRows {
  page: number;
  rows: Row[]; // sorted by y descending (top of page first)
}

/**
 * Right edge of the narrow "S.NO / SUBJECT" label column in PDF points,
 * measured from the real notification's own header cell (~x41-175) and
 * cross-checked on pages spanning ECE through Grade 8 — not a guess. The
 * Semester-I/Semester-II boundary is handled adaptively instead of with a
 * second fixed threshold — see `splitUnitColumns` below.
 */
const LABEL_MAX_X = 185;

/** Rows within this many PDF points of Y are treated as one visual line. */
const ROW_Y_TOLERANCE = 3;

async function extractPageRows(buffer: Buffer): Promise<PageRows[]> {
  const pages: PageRows[] = [];
  await pdfParse(buffer, {
    pagerender: (pageData: any) => {
      const renderOptions = { normalizeWhitespace: true, disableCombineTextItems: false };
      return pageData.getTextContent(renderOptions).then((textContent: any) => {
        const items: Item[] = (textContent.items as Array<{ str: string; transform: number[] }>)
          .filter((it) => it.str && it.str.trim().length > 0)
          .map((it) => ({ x: it.transform[4], y: it.transform[5], str: it.str }));

        items.sort((a, b) => b.y - a.y || a.x - b.x);

        const rows: Row[] = [];
        for (const item of items) {
          const openRow = rows[rows.length - 1];
          if (openRow && Math.abs(item.y - openRow.y) <= ROW_Y_TOLERANCE) {
            openRow.items.push(item);
          } else {
            rows.push({ y: item.y, items: [item] });
          }
        }
        for (const row of rows) row.items.sort((a, b) => a.x - b.x);

        pages.push({ page: pages.length + 1, rows });
        return '';
      });
    },
  });
  return pages;
}

function columnText(row: Row, xMin: number, xMax: number): string {
  return row.items
    .filter((it) => it.x >= xMin && it.x < xMax)
    .map((it) => it.str)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function itemsToText(items: Item[]): string {
  return items
    .map((it) => it.str)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * The Semester-I/Semester-II column boundary is NOT a fixed X value — it
 * shifts a little from block to block in the real PDF (observed: a
 * Semester-II item starting at x≈378.9 in one subject's table vs x≈388.9
 * in another). A fixed threshold misclassifies items sitting between those
 * values. Instead, for the non-label part of each row, find the single
 * largest horizontal gap between consecutive items (word-internal gaps run
 * ~3-10pt; the blank gutter between the two unit columns runs much wider)
 * and split there. If no gap that wide exists, the row has content in only
 * one of the two columns — decide which by comparing its average X to
 * `S1_S2_MIDPOINT_HINT`, a reference measured from real column centers.
 */
const MIN_COLUMN_GAP = 40;
const S1_S2_MIDPOINT_HINT = 370;

function splitUnitColumns(items: Item[]): { s1: Item[]; s2: Item[] } {
  if (items.length === 0) return { s1: [], s2: [] };
  let maxGap = -1;
  let splitIndex = -1;
  for (let i = 1; i < items.length; i++) {
    const gap = items[i].x - items[i - 1].x;
    if (gap > maxGap) {
      maxGap = gap;
      splitIndex = i;
    }
  }
  if (maxGap >= MIN_COLUMN_GAP) {
    return { s1: items.slice(0, splitIndex), s2: items.slice(splitIndex) };
  }
  const avgX = items.reduce((sum, it) => sum + it.x, 0) / items.length;
  return avgX < S1_S2_MIDPOINT_HINT ? { s1: items, s2: [] } : { s1: [], s2: items };
}

function fullRowText(row: Row): string {
  return row.items
    .map((it) => it.str)
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// --- Parsing heuristics ---------------------------------------------------

const GRADE_PATTERNS: Array<{ gradeId: string; re: RegExp }> = [
  { gradeId: 'ece', re: /^EARLY\s+CHILDHOOD\s+EDUCATION\b/i },
  { gradeId: 'grade-1', re: /^GRADE\s*[-\s]?1\b/i },
  { gradeId: 'grade-2', re: /^GRADE\s*[-\s]?2\b/i },
  { gradeId: 'grade-3', re: /^GRADE\s*[-\s]?3\b/i },
  { gradeId: 'grade-4', re: /^GRADE\s*[-\s]?4\b/i },
  { gradeId: 'grade-5', re: /^GRADE\s*[-\s]?5\b/i },
  { gradeId: 'grade-6', re: /^GRADE\s*[-\s]?6\b/i },
  { gradeId: 'grade-7', re: /^GRADE\s*[-\s]?7\b/i },
  { gradeId: 'grade-8', re: /^GRADE\s*[-\s]?8\b/i },
];

const SESSION_RE = /\b(20\d{2})\s*[-–]\s*(\d{2,4})\b/;
const URDU_RE = /[؀-ۿ]/;

/** Full-row header/footer captions to skip outright — never subject or unit data. */
const SKIP_ROW_PATTERNS: RegExp[] = [
  /^S\.?\s*NO\.?\s+SUBJECT$/i,
  /^SEMESTER\s*-?\s*I\s+SEMESTER\s*-?\s*II$/i,
  /^UNITS\s+UNITS$/i,
  /^Page\s+\d+\s+of\s+\d+$/i,
];

const SESSION_NOTE_RE = /^\(?\s*Session\b/i;

/**
 * Marks the end of the curriculum table: the notification closes with a
 * signature line ("DIRECTOR") and a circulation/distribution list
 * ("Endst: No. ...", "Copy forwarded for information to the: ...", a
 * numbered list of addressee offices). None of that is curriculum data —
 * once any of these is seen, parsing stops for the rest of the document.
 */
const DOCUMENT_END_RE = /^Endst\b|^Copy\s+fo\s*rwarded\b/i;

/** "Page No. 1 to 18" / "Page No. 1-18" style scope note instead of an itemized unit list. */
const PAGE_RANGE_RE = /Page\s*No\.?\s*\d/i;

/**
 * Urdu-script "سبق N تا M" / "صفحہ نمبر N تا M" (lesson/page RANGE) scope
 * note, used instead of an itemized unit list for a few regional-language
 * blocks. Deliberately NOT a bare test for the word "سبق" ("lesson") —
 * that word also appears inside plenty of ordinary unit titles (e.g.
 * "(سنانے کا سبق) ..." = "(narration lesson) ..."), so this instead
 * requires the range shape itself: the keyword, the range-connector "تا"
 * ("to"), and at least two separate numbers somewhere in the line —
 * order-independent, since RTL/LTR glyph-position quirks (see
 * extractPageRows) put them in varying sequence.
 */
function isUrduScopeRangeNote(text: string): boolean {
  const hasKeyword = /سبق|صفحہ/.test(text);
  const hasRangeWord = /تا/.test(text);
  const digitGroups = text.match(/\d+/g) ?? [];
  return hasKeyword && hasRangeWord && digitGroups.length >= 2;
}

const NUMBERED_ITEM_RE = /^(\d{1,3})\.\s*(.*)$/;
/**
 * Arabic/Urdu unit entries in this PDF put the item number at the END of
 * the line instead of the start (e.g. "قرآن مجید و حدیث نبوی . 1" — the
 * digit is not part of the Urdu phrase's word order; the trailing " . N"
 * is glyph-positioned last because of how this PDF lays out RTL text, not
 * because the source numbers items differently). Title order/word order
 * is NOT corrected — see the module header's "URDU/ARABIC-SCRIPT TEXT"
 * note — this only recognizes where the number is so the row is captured
 * as a unit AT ALL rather than silently dropped for lack of a leading
 * digit.
 */
const TRAILING_NUMBERED_ITEM_RE = /^(.+?)\s*\.\s*(\d{1,3})\s*$/;

/**
 * Known subject names, matched against the label column with all
 * whitespace/punctuation stripped (pdfjs sometimes splits a single word
 * across items, e.g. "SERAIKI" arriving as "S" + "ERAIKI" — comparing
 * compacted strings absorbs that). This is a RECOGNITION list, not an
 * exhaustive one: an unrecognized label is auto-registered from its own
 * text (see registerOrGetSubject) rather than dropped, since the notification
 * may use a subject name not anticipated here.
 */
const KNOWN_SUBJECTS: Array<{ compact: string; subjectId: string; name: string }> = [
  { compact: 'URDU', subjectId: 'urdu', name: 'Urdu' },
  { compact: 'ENGLISH', subjectId: 'english', name: 'English' },
  { compact: 'MATHEMATICS', subjectId: 'mathematics', name: 'Mathematics' },
  { compact: 'ISLAMIYAT', subjectId: 'islamiyat', name: 'Islamiyat' },
  { compact: 'ISLAMIAT', subjectId: 'islamiyat', name: 'Islamiyat' },
  { compact: 'NAZIRAEQURAN', subjectId: 'nazira-e-quran', name: 'Nazira-e-Quran' },
  { compact: 'MUTALAEQURAN', subjectId: 'mutala-e-quran', name: 'Mutala-e-Quran' },
  { compact: 'GENERALKNOWLEDGE', subjectId: 'general-knowledge', name: 'General Knowledge' },
  { compact: 'HINDKO', subjectId: 'hindko', name: 'Hindko' },
  { compact: 'PASHTO', subjectId: 'pashto', name: 'Pashto' },
  { compact: 'SERAIKI', subjectId: 'seraiki', name: 'Seraiki' },
  { compact: 'KHOWAR', subjectId: 'khowar', name: 'Khowar' },
  { compact: 'KOHISTANI', subjectId: 'kohistani', name: 'Kohistani' },
  { compact: 'ETHICSFORNONMUSLIMS', subjectId: 'ethics-for-non-muslims', name: 'Ethics for Non-Muslims' },
  { compact: 'GENERALSCIENCE', subjectId: 'general-science', name: 'General Science' },
  { compact: 'SOCIALSTUDIES', subjectId: 'social-studies', name: 'Social Studies' },
  { compact: 'HISTORY', subjectId: 'history', name: 'History' },
  { compact: 'GEOGRAPHY', subjectId: 'geography', name: 'Geography' },
  { compact: 'COMPUTEREDUCATION', subjectId: 'computer-education', name: 'Computer Education' },
  { compact: 'COMPUTERSCIENCE', subjectId: 'computer-science', name: 'Computer Science' },
  { compact: 'HOMEECONOMICS', subjectId: 'home-economics', name: 'Home Economics' },
  { compact: 'DRAWING', subjectId: 'drawing', name: 'Drawing' },
  { compact: 'HEALTHPHYSICALEDUCATION', subjectId: 'health-physical-education', name: 'Health & Physical Education' },
  { compact: 'HEALTHANDPHYSICALEDUCATION', subjectId: 'health-physical-education', name: 'Health & Physical Education' },
  { compact: 'PHYSICALEDUCATION', subjectId: 'physical-education', name: 'Physical Education' },
  { compact: 'ARABIC', subjectId: 'arabic', name: 'Arabic' },
  { compact: 'INTRODUCTIONTOTECHNOLOGIES', subjectId: 'introduction-to-technologies', name: 'Introduction to Technologies' },
  { compact: 'PAKISTANSTUDIES', subjectId: 'pakistan-studies', name: 'Pakistan Studies' },
  { compact: 'ARTSCRAFT', subjectId: 'art-craft', name: 'Arts & Craft' },
  { compact: 'ARTCRAFT', subjectId: 'art-craft', name: 'Arts & Craft' },
].sort((a, b) => b.compact.length - a.compact.length); // longest first so e.g. GENERALSCIENCE beats a bare SCIENCE prefix

function compactUpper(text: string): string {
  return text.toUpperCase().replace(/[^A-Z]/g, '');
}

interface SubjectInfo {
  subjectId: string;
  name: string;
}

const dynamicSubjects = new Map<string, SubjectInfo>(); // compact -> info, for auto-registered subjects

function slugify(text: string): string {
  return (
    text
      .trim()
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'subject'
  );
}

/**
 * Fuzzy match: true if `compact` is a prefix of a known subject's compact
 * name, OR vice versa. The "vice versa" half matters because a few
 * subjects (e.g. "ETHICS FOR NON-MUSLIM(S)") wrap across label rows with
 * no S.No of their own, so the FIRST line alone ("ETHICS FOR") is only a
 * prefix of the full known name, not the other way around; it also
 * absorbs real-document spelling variance (the PDF uses both
 * "NON-MUSLIM" and "NON-MUSLIMS" in different places).
 */
function fuzzyMatchKnown(compact: string, knownCompact: string): boolean {
  if (compact.startsWith(knownCompact)) return true;
  if (compact.length >= 6 && knownCompact.startsWith(compact)) return true;
  return false;
}

/** True only for a match against the static KNOWN_SUBJECTS list (never an auto-registered one). */
function matchesKnownSubject(labelText: string): boolean {
  const compact = compactUpper(labelText);
  return KNOWN_SUBJECTS.some((known) => fuzzyMatchKnown(compact, known.compact));
}

/**
 * Recognize (or auto-register) a subject from a label-column line. Returns
 * null if the line doesn't look like a subject header at all (too short,
 * no letters, or a session/S.No marker already filtered upstream).
 */
function resolveSubject(labelText: string): SubjectInfo | null {
  const trimmed = labelText.trim();
  const compact = compactUpper(trimmed);
  if (trimmed.length < 3) return null;

  if (compact.length >= 3) {
    for (const known of KNOWN_SUBJECTS) {
      if (fuzzyMatchKnown(compact, known.compact)) {
        return { subjectId: known.subjectId, name: known.name };
      }
    }
  }

  // Some subject names in this notification are written entirely in Urdu
  // (no Latin letters at all — e.g. one grade's "Health & Physical
  // Education" row), so `compact` alone can't identify or dedupe them.
  // Key auto-registration on the raw trimmed text itself (a content hash,
  // for a short stable id) instead of the Latin-only compact in that case.
  const dedupeKey = compact.length >= 3 ? compact : `urdu:${trimmed}`;
  if (dynamicSubjects.has(dedupeKey)) return dynamicSubjects.get(dedupeKey)!;

  // Auto-register an unrecognized subject from its own text — extraction,
  // not fabrication: the name is exactly what the PDF printed (Urdu
  // decorations like "( قاعدہ )" kept as part of the display name;
  // pure-Urdu names are kept verbatim rather than guessed/translated).
  const subjectId =
    compact.length >= 3
      ? slugify(compact) || slugify(trimmed)
      : `subject-${createHash('sha256').update(trimmed).digest('hex').slice(0, 10)}`;
  const info: SubjectInfo = { subjectId, name: trimmed };
  dynamicSubjects.set(dedupeKey, info);
  return info;
}

interface CurriculumRow {
  curriculumId: string;
  gradeId: string;
  subjectId: string;
  session: string;
  semester: string;
  unitNumber: number;
  unitTitle: string;
  unitTitleUrdu: string | null;
  description: null;
  sourceDocumentId: string;
  sourcePage: number;
  sourceUrl: string;
  version: number;
  needsVerification: true;
}

interface SubjectRow {
  subjectId: string;
  name: string;
  nameUrdu: string | null;
  gradeIds: string[];
  sortOrder: number;
  active: true;
}

function detectSession(pages: PageRows[], override: string | null): string {
  if (override) return override;
  for (const p of pages.slice(0, 3)) {
    for (const row of p.rows) {
      const m = fullRowText(row).match(SESSION_RE);
      if (m) {
        const end = m[2].length === 2 ? m[2] : m[2].slice(-2);
        return `${m[1]}-${end}`;
      }
    }
  }
  return 'unknown-session';
}

/** Mutable "currently open" numbered unit for one semester column, spanning wrapped lines and page breaks. */
interface OpenUnit {
  gradeId: string;
  subjectId: string;
  semester: 'Semester I' | 'Semester II';
  unitNumber: number;
  titleParts: string[];
  sourcePage: number;
}

function buildTitleFields(rawTitle: string): { unitTitle: string; unitTitleUrdu: string | null } {
  const title = rawTitle.replace(/\s+/g, ' ').trim();
  if (URDU_RE.test(title)) {
    // Preserved verbatim, uncorrected — see the module header comment
    // "URDU/ARABIC-SCRIPT TEXT" for why no reordering is attempted.
    return { unitTitle: title, unitTitleUrdu: title };
  }
  return { unitTitle: title, unitTitleUrdu: null };
}

function parsePages(pages: PageRows[], session: string, sourceUrl: string, sourceDocumentId: string) {
  const curriculum: CurriculumRow[] = [];
  const subjectGradeMap = new Map<string, { info: SubjectInfo; grades: Set<string> }>();
  const curriculumIdCounts = new Map<string, number>(); // dedupe safety: base id -> count seen

  let currentGrade: string | null = null;
  let currentSubject: SubjectInfo | null = null;
  let openS1: OpenUnit | null = null;
  let openS2: OpenUnit | null = null;

  function registerSubjectForGrade(info: SubjectInfo, gradeId: string) {
    if (!subjectGradeMap.has(info.subjectId)) {
      subjectGradeMap.set(info.subjectId, { info, grades: new Set() });
    }
    subjectGradeMap.get(info.subjectId)!.grades.add(gradeId);
  }

  function pushCurriculumRow(open: OpenUnit) {
    const { unitTitle, unitTitleUrdu } = buildTitleFields(open.titleParts.join(' '));
    if (!unitTitle) return;
    const baseId = `${open.gradeId}-${open.subjectId}-${open.semester.toLowerCase().replace(/\s+/g, '-')}-unit-${open.unitNumber}`;
    const seen = curriculumIdCounts.get(baseId) ?? 0;
    curriculumIdCounts.set(baseId, seen + 1);
    const curriculumId = seen === 0 ? baseId : `${baseId}-${seen + 1}`;

    curriculum.push({
      curriculumId,
      gradeId: open.gradeId,
      subjectId: open.subjectId,
      session,
      semester: open.semester,
      unitNumber: open.unitNumber,
      unitTitle,
      unitTitleUrdu,
      description: null,
      sourceDocumentId,
      sourcePage: open.sourcePage,
      sourceUrl,
      version: 1,
      needsVerification: true,
    });
  }

  function flushOpenUnits() {
    if (openS1) pushCurriculumRow(openS1);
    if (openS2) pushCurriculumRow(openS2);
    openS1 = null;
    openS2 = null;
  }

  function pushScopeNote(semester: 'Semester I' | 'Semester II', text: string, page: number) {
    if (!currentGrade || !currentSubject) return;
    const { unitTitle, unitTitleUrdu } = buildTitleFields(text);
    if (!unitTitle) return;
    pushCurriculumRow({
      gradeId: currentGrade,
      subjectId: currentSubject.subjectId,
      semester,
      unitNumber: 0,
      titleParts: [unitTitle],
      sourcePage: page,
    });
    if (unitTitleUrdu) {
      // buildTitleFields already folded Urdu in; nothing further to do —
      // this branch exists only to keep the intent obvious for readers.
    }
  }

  function handleColumn(
    text: string,
    page: number,
    semester: 'Semester I' | 'Semester II',
    getOpen: () => OpenUnit | null,
    setOpen: (u: OpenUnit | null) => void,
  ) {
    if (!text) return;
    if (!currentGrade || !currentSubject) return;

    if (PAGE_RANGE_RE.test(text) || isUrduScopeRangeNote(text)) {
      // Scope-note subject (e.g. regional-language primer): no itemized
      // units in the source, so store the note itself rather than invent
      // per-lesson titles. Finalize any open numbered unit in this column
      // first (shouldn't normally coexist, but stay safe).
      const open = getOpen();
      if (open) {
        pushCurriculumRow(open);
        setOpen(null);
      }
      pushScopeNote(semester, text, page);
      return;
    }

    const leading = text.match(NUMBERED_ITEM_RE);
    const trailing = !leading && URDU_RE.test(text) ? text.match(TRAILING_NUMBERED_ITEM_RE) : null;
    if (leading || trailing) {
      const [unitNumber, title] = leading ? [leading[1], leading[2]] : [trailing![2], trailing![1]];
      const open = getOpen();
      if (open) pushCurriculumRow(open);
      setOpen({
        gradeId: currentGrade,
        subjectId: currentSubject.subjectId,
        semester,
        unitNumber: parseInt(unitNumber, 10),
        titleParts: [title],
        sourcePage: page,
      });
      return;
    }

    // Continuation of a wrapped title, or stray decoration (e.g. a lone
    // "•" bullet) — only attach if a unit is actually open.
    const open = getOpen();
    if (open) {
      open.titleParts.push(text);
    }
  }

  // Multi-word subject names wrap across several label-column rows — and,
  // unlike a simple "name block, then units" layout, the unit columns for
  // that subject's first few rows are laid out ALONGSIDE those wrapping
  // name lines rather than after them (observed e.g. for "General
  // Knowledge": row1 = S.No + unit-1 + unit-7, row2 = "GENERAL" (label
  // only) + unit-2 + unit-8, row3 = "KNOWLEDGE" (label only) + unit-3 +
  // unit-9, row4 = "(Session ...)" + unit-4 + unit-10). So while a
  // subject's name is still being accumulated (`pending === true`), its
  // unit rows can't be attributed to a subjectId yet — they're queued in
  // `pendingEvents` and replayed through handleColumn once the "(Session
  // ...)" row resolves the name.
  let labelBuffer: string[] = [];
  let pending = false;
  let pendingEvents: Array<{ s1: string; s2: string; page: number }> = [];

  function startNewSubjectBlock() {
    resolveLabelBuffer(); // finalize whatever the previous block resolved to, if not already
    flushOpenUnits();
    currentSubject = null;
    labelBuffer = [];
    pendingEvents = [];
    pending = true;
  }

  function resolveLabelBuffer() {
    if (!pending) return;
    const combined = labelBuffer.join(' ');
    labelBuffer = [];
    pending = false;
    const events = pendingEvents;
    pendingEvents = [];
    if (!currentGrade) return; // discards text seen before the first grade heading (e.g. the notification's intro paragraph)

    const subject = combined ? resolveSubject(combined) : null;
    if (subject) {
      currentSubject = subject;
      registerSubjectForGrade(subject, currentGrade);
    }
    if (!currentSubject) return; // nothing sensible to attribute these units to
    for (const ev of events) {
      handleColumn(ev.s1, ev.page, 'Semester I', () => openS1, (u) => (openS1 = u));
      handleColumn(ev.s2, ev.page, 'Semester II', () => openS2, (u) => (openS2 = u));
    }
  }

  outer: for (const { page, rows } of pages) {
    for (const row of rows) {
      const whole = fullRowText(row);
      if (!whole) continue;
      if (DOCUMENT_END_RE.test(whole)) break outer; // signature/distribution-list footer — not curriculum data
      if (SKIP_ROW_PATTERNS.some((re) => re.test(whole))) continue;

      let matchedGrade: string | null = null;
      for (const g of GRADE_PATTERNS) {
        if (g.re.test(whole)) {
          matchedGrade = g.gradeId;
          break;
        }
      }
      if (matchedGrade) {
        pending = false; // discard any incomplete block — a grade heading always starts fresh
        labelBuffer = [];
        pendingEvents = [];
        if (matchedGrade !== currentGrade) {
          flushOpenUnits();
          currentGrade = matchedGrade;
          currentSubject = null;
        }
        continue; // heading row carries nothing else
      }

      const labelText = columnText(row, 0, LABEL_MAX_X);
      const leadingNumber = labelText.match(/^(\d{1,2})\.\s*(.*)$/);
      if (leadingNumber) {
        // A new S.No always marks the first row of a new subject block,
        // whether or not the rest of the name is on this same row.
        startNewSubjectBlock();
        if (leadingNumber[2]) labelBuffer.push(leadingNumber[2]);
      } else if (labelText && SESSION_NOTE_RE.test(labelText)) {
        resolveLabelBuffer(); // "(Session ...)" closes the accumulated name block
      } else if (labelText && !pending && matchesKnownSubject(labelText)) {
        // Some subjects — observed for the regional-language options
        // (Hindko/Pashto/Seraiki/Khowar) listed as alternatives under a
        // grade's main language — have NO S.No of their own at all, so the
        // only boundary signal is their name matching a recognized subject
        // outright while nothing else is pending.
        startNewSubjectBlock();
        labelBuffer.push(labelText);
      } else if (labelText && pending) {
        labelBuffer.push(labelText);
      }

      const nonLabelItems = row.items.filter((it) => it.x >= LABEL_MAX_X);
      const { s1, s2 } = splitUnitColumns(nonLabelItems);
      const s1Text = itemsToText(s1);
      const s2Text = itemsToText(s2);
      if (pending) {
        if (s1Text || s2Text) pendingEvents.push({ s1: s1Text, s2: s2Text, page });
      } else {
        handleColumn(s1Text, page, 'Semester I', () => openS1, (u) => (openS1 = u));
        handleColumn(s2Text, page, 'Semester II', () => openS2, (u) => (openS2 = u));
      }
    }
  }
  resolveLabelBuffer();
  flushOpenUnits();

  const subjects: SubjectRow[] = Array.from(subjectGradeMap.values()).map(({ info, grades }, i) => ({
    subjectId: info.subjectId,
    name: info.name,
    // A handful of subjects in this notification have no Latin name at
    // all (see resolveSubject's "pure-Urdu" branch) — `name` is then the
    // raw Urdu text itself, so surface it as `nameUrdu` too rather than
    // leaving it null, so the app can render it RTL.
    nameUrdu: URDU_RE.test(info.name) ? info.name : null,
    gradeIds: Array.from(grades).sort(),
    sortOrder: i,
    active: true,
  }));

  return { curriculum, subjects };
}

// --- Debug dump ------------------------------------------------------------

function printDebug(pages: PageRows[]): void {
  console.log('');
  console.log('--debug: reconstructed rows per page, split into [label | Semester I | Semester II] ---');
  for (const { page, rows } of pages) {
    console.log(`\n----- page ${page} -----`);
    for (const row of rows) {
      const label = columnText(row, 0, LABEL_MAX_X);
      const nonLabelItems = row.items.filter((it) => it.x >= LABEL_MAX_X);
      const { s1, s2 } = splitUnitColumns(nonLabelItems);
      const s1Text = itemsToText(s1);
      const s2Text = itemsToText(s2);
      if (!label && !s1Text && !s2Text) continue;
      console.log(`y=${row.y.toFixed(1)}\t[L] ${label}\t[S1] ${s1Text}\t[S2] ${s2Text}`);
    }
  }
  console.log('------------------------------------------------------------------');
  console.log('');
}

// --- Main -----------------------------------------------------------------

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!fs.existsSync(args.pdfPath)) {
    console.error(`PDF not found at: ${args.pdfPath}`);
    process.exit(1);
  }

  const buffer = fs.readFileSync(args.pdfPath);
  console.log(`Read ${buffer.byteLength} bytes from ${args.pdfPath}. Extracting text per page…`);

  let pages: PageRows[];
  try {
    pages = await extractPageRows(buffer);
  } catch (parseErr) {
    console.error(
      [
        '',
        'COULD NOT PARSE PDF',
        '--------------------',
        `pdf-parse failed to read ${args.pdfPath}: ${(parseErr as Error).message}`,
        'The file may be corrupted, password-protected, or not a valid PDF.',
        'Re-download it from the official source and try again. Nothing was written.',
        '',
      ].join('\n'),
    );
    process.exit(1);
  }

  const totalChars = pages.reduce((sum, p) => sum + p.rows.reduce((s, r) => s + fullRowText(r).length, 0), 0);

  if (args.debug) printDebug(pages);

  if (totalChars < 200) {
    console.error(
      [
        '',
        'NO EXTRACTABLE TEXT',
        '--------------------',
        `Only ${totalChars} characters of text were found across ${pages.length} page(s).`,
        'This usually means the PDF is a scanned image without a text layer,',
        'so pattern-matching cannot read it. Nothing was written.',
        '',
        'Next steps:',
        '  1. Run it through OCR first (e.g. the `pdf` skill/tooling, or',
        '     `ocrmypdf input.pdf output-ocr.pdf`) to add a text layer, then',
        '     re-run this script against output-ocr.pdf.',
        '  2. Or transcribe the content manually into',
        '     scripts/seed/subjects.json / scripts/seed/curriculum.json',
        '     using scripts/seed/subjects.schema-example.json and',
        '     scripts/seed/curriculum.schema-example.json as the field',
        '     reference — every row must still carry needsVerification: true',
        '     until an admin confirms it against the PDF.',
        '',
      ].join('\n'),
    );
    process.exit(1);
  }

  const session = detectSession(pages, args.session);
  const sourceDocumentId = 'dcte-semester-notification-' + session;
  const { curriculum, subjects } = parsePages(pages, session, args.sourceUrl, sourceDocumentId);

  const byGrade = new Map<string, number>();
  for (const c of curriculum) byGrade.set(c.gradeId, (byGrade.get(c.gradeId) ?? 0) + 1);

  console.log('');
  console.log('Extraction summary');
  console.log('-------------------');
  console.log(`Pages processed:         ${pages.length}`);
  console.log(`Session detected:        ${session}${args.session ? '' : ' (auto-detected — pass --session=YYYY-YY to override)'}`);
  console.log(`Grades found:            ${byGrade.size} (${Array.from(byGrade.keys()).join(', ')})`);
  console.log(`Subjects discovered:     ${subjects.length}`);
  console.log(`Curriculum records:      ${curriculum.length}`);
  console.log(`Records needing review:  ${curriculum.filter((c) => c.needsVerification).length} (should be all of them)`);
  console.log(`Records with Urdu text:  ${curriculum.filter((c) => c.unitTitleUrdu).length}`);
  console.log('All rows are written with needsVerification: true — review before flipping to false.');
  console.log('');

  if (curriculum.length === 0) {
    console.error(
      'Text was extracted but no grade/subject/unit patterns were matched. The notification ' +
        'may use different wording/layout than expected — re-run with --debug to see the ' +
        'reconstructed [label | Semester I | Semester II] columns per row, and adjust ' +
        'GRADE_PATTERNS / KNOWN_SUBJECTS / NUMBERED_ITEM_RE / LABEL_MAX_X / MIN_COLUMN_GAP in this ' +
        'script to match. Nothing was written.',
    );
    process.exit(1);
  }

  if (args.dryRun) {
    console.log('--dry-run set: not writing files. Sample of first 5 curriculum rows:');
    console.log(JSON.stringify(curriculum.slice(0, 5), null, 2));
    return;
  }

  fs.mkdirSync(args.outDir, { recursive: true });
  const subjectsPath = path.join(args.outDir, 'subjects.json');
  const curriculumPath = path.join(args.outDir, 'curriculum.json');
  fs.writeFileSync(subjectsPath, JSON.stringify(subjects, null, 2));
  fs.writeFileSync(curriculumPath, JSON.stringify(curriculum, null, 2));

  console.log(`Wrote ${subjects.length} subjects to ${subjectsPath}`);
  console.log(`Wrote ${curriculum.length} curriculum records to ${curriculumPath}`);
  console.log('');
  console.log('Next: review both files by hand against the PDF, then run `npm run seed`.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

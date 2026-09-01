/**
 * scripts/seed/confidence.ts
 * ---------------------------------------------------------------------------
 * Validation + confidence classification for extracted curriculum records,
 * run once at seed time (see import_seed.ts's `importCurriculum`). This is
 * the single source of truth for `extractionConfidence` and `validation` —
 * the admin dashboard (admin/index.html) and the bulk-approve Cloud
 * Functions (functions/src/admin/adminApi.ts) only ever READ these fields
 * back from Firestore; they never recompute them, so there is exactly one
 * place this logic lives.
 *
 * CLASSIFICATION RULES
 * ---------------------------------------------------------------------------
 *   LOW    — any hard validation check fails, OR the title looks
 *            OCR/glyph-scrambled, OR it's a non-itemized "scope note"
 *            record (unitNumber 0 — e.g. "Page No. 1 to 18"). LOW records
 *            are NEVER eligible for bulk approval; every one must be
 *            opened and read individually.
 *   MEDIUM — passes every hard validation check and isn't flagged as
 *            OCR-suspect, but the title contains Arabic-script (Urdu)
 *            text. Per the project's own rule ("be especially conservative
 *            for Urdu, because extraction can corrupt it"), Urdu text is
 *            NEVER classified HIGH, no matter how clean it looks —
 *            MEDIUM records need a human to actually read them (fast),
 *            just not the same page-by-page scrutiny as LOW.
 *   HIGH   — passes every hard validation check, no Urdu script, not
 *            OCR-suspect, and is a real itemized unit (unitNumber > 0).
 *            Only HIGH records are eligible for "Approve High Confidence"
 *            bulk actions.
 */

export type ExtractionConfidence = 'HIGH' | 'MEDIUM' | 'LOW';

export interface ValidationResult {
  gradeExists: boolean;
  subjectExists: boolean;
  semesterValid: boolean;
  sourcePageExists: boolean;
  sourceDocumentIdExists: boolean;
  sourceUrlExists: boolean;
  titleNotEmpty: boolean;
  isDuplicate: boolean;
  ocrSuspect: boolean;
  /** True only if every check above (other than ocrSuspect, tracked separately) passes. */
  passed: boolean;
  /** Human-readable reasons for anything that failed, for the review UI. */
  issues: string[];
}

export interface ClassifiableRecord {
  curriculumId: string;
  gradeId?: string;
  subjectId?: string;
  semester?: string;
  unitNumber?: number;
  unitTitle?: string;
  unitTitleUrdu?: string | null;
  sourcePage?: number | null;
  sourceDocumentId?: string;
  sourceUrl?: string;
}

const URDU_RE = /[؀-ۿ]/;
const VALID_SEMESTERS = new Set(['Semester I', 'Semester II']);

/**
 * Best-effort OCR/glyph-scramble detector for Arabic-script text. This PDF
 * extractor is known (see scripts/import_dcte_pdf.ts's module header) to
 * sometimes bleed isolated diacritic glyphs from a neighboring honorific
 * phrase into a title, producing many single-character "words" — that
 * pattern is what this checks for. It is a heuristic, not a guarantee: a
 * clean pass does NOT mean the text is correct, only that it's not
 * obviously scrambled. Non-Urdu text is never flagged by this check.
 *
 * The single-character-word ratio only kicks in above a minimum word
 * count (`MIN_WORDS_FOR_RATIO_CHECK`) — a short, completely legitimate
 * phrase very often contains one single-letter word (e.g. "و", "and"),
 * which would otherwise push a 3-word phrase over a naive ratio threshold
 * and mark ordinary text as suspect. A high absolute word count on its own
 * (`MAX_WORDS`) is independently suspicious regardless of ratio, since the
 * observed corruption pattern is a title that "grows" many extra
 * single-glyph tokens from a bled-in honorific phrase.
 */
const MIN_WORDS_FOR_RATIO_CHECK = 6;
const SINGLE_CHAR_RATIO_THRESHOLD = 0.35;
const MAX_WORDS = 15;

export function isOcrSuspect(text: string): boolean {
  if (!text || !URDU_RE.test(text)) return false;
  const words = text.trim().split(/\s+/).filter(Boolean);
  if (words.length === 0) return false;
  if (words.length > MAX_WORDS) return true;
  if (words.length < MIN_WORDS_FOR_RATIO_CHECK) return false;
  const singleCharWords = words.filter((w) => w.length === 1).length;
  return singleCharWords / words.length > SINGLE_CHAR_RATIO_THRESHOLD;
}

export function validateRecord(
  record: ClassifiableRecord,
  knownGradeIds: ReadonlySet<string>,
  knownSubjectIds: ReadonlySet<string>,
  knownDocumentIds: ReadonlySet<string>,
  duplicateKeys: ReadonlySet<string>,
): ValidationResult {
  const issues: string[] = [];

  const gradeExists = !!record.gradeId && knownGradeIds.has(record.gradeId);
  if (!gradeExists) issues.push(`Unknown gradeId "${record.gradeId}"`);

  const subjectExists = !!record.subjectId && knownSubjectIds.has(record.subjectId);
  if (!subjectExists) issues.push(`Unknown subjectId "${record.subjectId}"`);

  const semesterValid = !!record.semester && VALID_SEMESTERS.has(record.semester);
  if (!semesterValid) issues.push(`Invalid semester "${record.semester}"`);

  const sourcePageExists = typeof record.sourcePage === 'number' && record.sourcePage > 0;
  if (!sourcePageExists) issues.push('Missing or invalid sourcePage');

  const sourceDocumentIdExists = !!record.sourceDocumentId && knownDocumentIds.has(record.sourceDocumentId);
  if (!sourceDocumentIdExists) issues.push(`Unknown sourceDocumentId "${record.sourceDocumentId}"`);

  const sourceUrlExists = !!record.sourceUrl && /^https?:\/\//i.test(record.sourceUrl);
  if (!sourceUrlExists) issues.push('Missing or invalid sourceUrl');

  const titleNotEmpty = !!record.unitTitle && record.unitTitle.trim().length > 0;
  if (!titleNotEmpty) issues.push('Empty unitTitle');

  const dedupeKey = `${record.gradeId}|${record.subjectId}|${record.semester}|${record.unitNumber}`;
  const isDuplicate = duplicateKeys.has(dedupeKey);
  if (isDuplicate) issues.push('Duplicate (gradeId, subjectId, semester, unitNumber) combination');

  const ocrSuspect = isOcrSuspect(record.unitTitle ?? '') || isOcrSuspect(record.unitTitleUrdu ?? '');
  if (ocrSuspect) issues.push('Title looks OCR/glyph-scrambled (many isolated Arabic-script fragments)');

  const passed =
    gradeExists &&
    subjectExists &&
    semesterValid &&
    sourcePageExists &&
    sourceDocumentIdExists &&
    sourceUrlExists &&
    titleNotEmpty &&
    !isDuplicate;

  return {
    gradeExists,
    subjectExists,
    semesterValid,
    sourcePageExists,
    sourceDocumentIdExists,
    sourceUrlExists,
    titleNotEmpty,
    isDuplicate,
    ocrSuspect,
    passed,
    issues,
  };
}

export function classifyConfidence(record: ClassifiableRecord, validation: ValidationResult): ExtractionConfidence {
  if (!validation.passed || validation.ocrSuspect) return 'LOW';
  if ((record.unitNumber ?? 0) <= 0) return 'LOW'; // scope-note record (e.g. "Page No. 1 to 18"), not an itemized unit
  const hasUrdu = URDU_RE.test(record.unitTitle ?? '') || URDU_RE.test(record.unitTitleUrdu ?? '');
  if (hasUrdu) return 'MEDIUM'; // never HIGH — see module header
  return 'HIGH';
}

/**
 * Find every (gradeId, subjectId, semester, unitNumber) tuple that appears
 * more than once — but only among unitNumber > 0 (real itemized units).
 * unitNumber 0 marks a scope-note record (e.g. "Page No. 1 to 18"), and a
 * subject can legitimately carry more than one scope note per semester
 * (e.g. Grade 1 Khowar has both a lesson-range note and a separate
 * page-range note for the same semester) — those are not duplicates, so
 * excluding them here avoids flagging every scope-note subject as having
 * "duplicate" records.
 */
export function findDuplicateKeys(records: ClassifiableRecord[]): Set<string> {
  const seen = new Map<string, number>();
  for (const r of records) {
    if ((r.unitNumber ?? 0) <= 0) continue;
    const key = `${r.gradeId}|${r.subjectId}|${r.semester}|${r.unitNumber}`;
    seen.set(key, (seen.get(key) ?? 0) + 1);
  }
  const duplicates = new Set<string>();
  for (const [key, count] of seen) {
    if (count > 1) duplicates.add(key);
  }
  return duplicates;
}

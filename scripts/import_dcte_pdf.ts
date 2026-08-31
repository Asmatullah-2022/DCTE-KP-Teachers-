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
 * "CONNECT tunnel failed, response 403"). It cannot download or read the
 * PDF's actual text, and per the app's own accuracy rule — never invent
 * missing unit titles, never silently guess — no curriculum content is
 * fabricated anywhere in this repository. This script is the real,
 * complete extraction pipeline; you run it once you have the PDF file
 * locally (downloaded in your own browser, where the government site is
 * reachable), and it produces the actual seed/subjects.json and
 * seed/curriculum.json files from the PDF's real text.
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
 * WHAT IT EXTRACTS
 * ---------------------------------------------------------------------------
 * Per curriculum unit: grade, subject, session, semester, unit number, unit
 * title, source page, source URL. Output rows always carry
 * sourceDocumentId / sourcePage / sourceUrl per the schema, and are always
 * written with `needsVerification: true` — this script performs pattern
 * matching, not OCR/NLP comprehension, so nothing it produces should be
 * treated as authoritative without a human comparing it to the PDF. If a
 * line looks like it contains Urdu (Arabic-script) text, it is preserved
 * verbatim in `unitTitleUrdu`; if the script cannot confidently separate an
 * Urdu segment from the English title on the same line, `unitTitleUrdu` is
 * left null rather than guessed.
 *
 * If the PDF contains no extractable text at all (i.e. it is a scanned
 * image rather than a text-layer PDF), this script will say so plainly and
 * write nothing — see "NO EXTRACTABLE TEXT" below for what to do next.
 *
 * If a real DCTE/KPESE PDF uses different wording than expected (e.g.
 * "Chapter" instead of "Unit", or a subject name not in SUBJECT_PATTERNS
 * below), pass `--debug` to print the raw text this script reconstructed
 * per page BEFORE any pattern matching runs, so you can see exactly what
 * it saw and adjust GRADE_PATTERNS / SUBJECT_PATTERNS / UNIT_RE / SESSION_RE
 * accordingly. `--dry-run` combined with `--debug` is the fastest way to
 * iterate without writing files each time.
 *
 * TESTED: this script's full pipeline (page-aware text extraction via
 * Y-coordinate line reconstruction, grade/subject/semester/unit detection,
 * session auto-detection, source-page attribution, and the
 * NO-EXTRACTABLE-TEXT / NO-PATTERNS-MATCHED / COULD-NOT-PARSE guard rails)
 * has been run end-to-end against a synthetic multi-page PDF built to
 * mirror the real notification's structure (grade/subject/semester
 * headers + "Unit N: Title" lines) and correctly produced subjects.json /
 * curriculum.json with accurate sourcePage values — see the project's
 * development history for that fixture. It has NOT been run against the
 * actual DCTE PDF, since this project has never been able to download it
 * (see "WHY THIS RUNS LOCALLY, NOT IN THIS SANDBOX" above).
 */
import * as fs from 'fs';
import * as path from 'path';

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

// --- PDF text extraction, page-aware -----------------------------------

interface PageText {
  page: number;
  text: string;
}

/**
 * Extract text per page (not just one big blob) so sourcePage is accurate,
 * AND rebuild real lines from glyph positions.
 *
 * pdfjs's `hasEOL` flag on text items is unreliable across PDF producers
 * (many tools emit one positioned text-showing operation per line without
 * ever setting it), so it cannot be trusted as the sole line-break signal.
 * Instead this groups text items by their Y coordinate
 * (`item.transform[5]`, rounded to absorb sub-pixel jitter within one
 * visual line) and sorts each group left-to-right by X — the standard
 * technique for recovering a PDF's visual line layout from pdfjs text
 * content, and what makes "Unit 1: Numbers and Operations" survive as one
 * line instead of being scrambled together with every other line on the
 * page.
 */
async function extractPages(buffer: Buffer): Promise<PageText[]> {
  const pages: PageText[] = [];
  await pdfParse(buffer, {
    pagerender: (pageData: any) => {
      const renderOptions = { normalizeWhitespace: true, disableCombineTextItems: false };
      return pageData.getTextContent(renderOptions).then((textContent: any) => {
        const lineMap = new Map<number, Array<{ x: number; str: string }>>();
        for (const item of textContent.items as Array<{ str: string; transform: number[] }>) {
          if (!item.str) continue;
          const y = Math.round(item.transform[5]);
          if (!lineMap.has(y)) lineMap.set(y, []);
          lineMap.get(y)!.push({ x: item.transform[4], str: item.str });
        }
        // PDF Y increases upward — sort descending so the first line is the
        // topmost line on the page.
        const orderedYs = Array.from(lineMap.keys()).sort((a, b) => b - a);
        const text = orderedYs
          .map((y) =>
            lineMap
              .get(y)!
              .sort((a, b) => a.x - b.x)
              .map((i) => i.str)
              .join(' ')
              .replace(/\s+/g, ' ')
              .trim(),
          )
          .filter(Boolean)
          .join('\n');
        pages.push({ page: pages.length + 1, text });
        return text;
      });
    },
  });
  return pages;
}

// --- Parsing heuristics ---------------------------------------------------

const GRADE_PATTERNS: Array<{ gradeId: string; re: RegExp }> = [
  { gradeId: 'ece', re: /\bECE\b|\bEarly\s+Childhood\s+Education\b/i },
  { gradeId: 'grade-1', re: /\bGrade[\s\-]?(I|1)\b(?!\d)/i },
  { gradeId: 'grade-2', re: /\bGrade[\s\-]?(II|2)\b/i },
  { gradeId: 'grade-3', re: /\bGrade[\s\-]?(III|3)\b/i },
  { gradeId: 'grade-4', re: /\bGrade[\s\-]?(IV|4)\b/i },
  { gradeId: 'grade-5', re: /\bGrade[\s\-]?(V|5)\b(?!I)/i },
  { gradeId: 'grade-6', re: /\bGrade[\s\-]?(VI|6)\b/i },
  { gradeId: 'grade-7', re: /\bGrade[\s\-]?(VII|7)\b/i },
  { gradeId: 'grade-8', re: /\bGrade[\s\-]?(VIII|8)\b/i },
];

const SEMESTER_RE = /Semester[\s\-]?(I{1,2}|1|2)\b/i;
const UNIT_RE = /\b(?:Unit|Chapter|Topic)[\s\-]?(\d{1,2})\s*[:\-]\s*(.+)/i;
const SESSION_RE = /\b(20\d{2})\s*[-–]\s*(\d{2,4})\b/;
const URDU_RE = /[؀-ۿ]/;

/**
 * Known subject-name tokens used only to RECOGNIZE a line already present
 * in the PDF as a subject header — this never invents a subject that isn't
 * literally in the source text. Extend this list if the real notification
 * uses subject names not covered here; unmatched subject headers are simply
 * not detected (safer than guessing).
 */
const SUBJECT_PATTERNS: Array<{ subjectId: string; re: RegExp }> = [
  { subjectId: 'urdu', re: /^\s*Urdu\s*$/i },
  { subjectId: 'english', re: /^\s*English\s*$/i },
  { subjectId: 'mathematics', re: /^\s*Mathematics\s*$/i },
  { subjectId: 'general-science', re: /^\s*(General\s+)?Science\s*$/i },
  { subjectId: 'social-studies', re: /^\s*Social\s+Studies\s*$/i },
  { subjectId: 'islamiyat', re: /^\s*Islamiyat\s*$/i },
  { subjectId: 'pakistan-studies', re: /^\s*Pakistan\s+Studies\s*$/i },
  { subjectId: 'computer-science', re: /^\s*Computer\s+Science\s*$/i },
  { subjectId: 'physical-education', re: /^\s*Physical\s+Education\s*$/i },
  { subjectId: 'art-craft', re: /^\s*Arts?\s*(&|and)?\s*Craft\s*$/i },
  { subjectId: 'pashto', re: /^\s*Pashto\s*$/i },
  { subjectId: 'hindko', re: /^\s*Hindko\s*$/i },
  { subjectId: 'khowar', re: /^\s*Khowar\s*$/i },
  { subjectId: 'kohistani', re: /^\s*Kohistani\s*$/i },
  { subjectId: 'seraiki', re: /^\s*Seraiki\s*$/i },
];

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
  nameUrdu: null;
  gradeIds: string[];
  sortOrder: number;
  active: true;
}

function normalizeSemester(raw: string): string {
  const n = raw.replace(/[\s\-]/g, '').toUpperCase();
  if (n === 'I' || n === '1') return 'Semester I';
  if (n === 'II' || n === '2') return 'Semester II';
  return `Semester ${raw}`;
}

function detectSession(pages: PageText[], override: string | null): string {
  if (override) return override;
  for (const p of pages.slice(0, 5)) {
    const m = p.text.match(SESSION_RE);
    if (m) {
      const end = m[2].length === 2 ? m[2] : m[2].slice(-2);
      return `${m[1]}-${end}`;
    }
  }
  return 'unknown-session';
}

function subjectDisplayName(subjectId: string): string {
  return subjectId
    .split('-')
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

function parsePages(pages: PageText[], session: string, sourceUrl: string, sourceDocumentId: string) {
  const curriculum: CurriculumRow[] = [];
  const subjectGradeMap = new Map<string, Set<string>>();

  let currentGrade: string | null = null;
  let currentSubject: string | null = null;
  let currentSemester: string | null = null;
  const unitCounters = new Map<string, number>(); // key: grade|subject|semester -> last seen unit number, for dedupe

  for (const { page, text } of pages) {
    // Split on the real line breaks preserved by extractPages()'s `hasEOL`
    // handling. Do NOT additionally split on ':' or '.' — "Unit 1: Numbers
    // and Operations" is one logical line and must stay intact for UNIT_RE
    // to capture the title after the colon.
    const lines = text
      .split(/\n|\r/)
      .map((l) => l.trim())
      .filter(Boolean);

    for (const line of lines) {
      for (const g of GRADE_PATTERNS) {
        if (g.re.test(line)) {
          currentGrade = g.gradeId;
          break;
        }
      }

      for (const s of SUBJECT_PATTERNS) {
        if (s.re.test(line)) {
          currentSubject = s.subjectId;
          if (currentGrade) {
            if (!subjectGradeMap.has(currentSubject)) subjectGradeMap.set(currentSubject, new Set());
            subjectGradeMap.get(currentSubject)!.add(currentGrade);
          }
          break;
        }
      }

      const semMatch = line.match(SEMESTER_RE);
      if (semMatch) {
        currentSemester = normalizeSemester(semMatch[1]);
      }

      const unitMatch = line.match(UNIT_RE);
      if (unitMatch && currentGrade && currentSubject && currentSemester) {
        const unitNumber = parseInt(unitMatch[1], 10);
        let titlePart = unitMatch[2].trim();

        let unitTitleUrdu: string | null = null;
        if (URDU_RE.test(titlePart)) {
          // If the whole remainder is Urdu, keep it as the Urdu title and
          // leave the English title as read (do not translate/guess).
          const englishOnly = titlePart.replace(/[؀-ۿ\s.,،]+/g, ' ').trim();
          if (englishOnly.length > 2) {
            unitTitleUrdu = titlePart.match(/[؀-ۿ][؀-ۿ\s.,،]*[؀-ۿ]/)?.[0]?.trim() ?? null;
            titlePart = englishOnly;
          } else {
            unitTitleUrdu = titlePart;
            titlePart = englishOnly || titlePart;
          }
        }

        const dedupeKey = `${currentGrade}|${currentSubject}|${currentSemester}`;
        const lastUnit = unitCounters.get(dedupeKey) ?? 0;
        // Skip an exact immediate repeat (e.g. the same "Unit N" caption
        // appearing in a running header/footer on consecutive lines).
        if (unitNumber === lastUnit) continue;
        unitCounters.set(dedupeKey, unitNumber);

        const curriculumId = `${currentGrade}-${currentSubject}-${currentSemester
          .toLowerCase()
          .replace(/\s+/g, '-')}-unit-${unitNumber}`;

        curriculum.push({
          curriculumId,
          gradeId: currentGrade,
          subjectId: currentSubject,
          session,
          semester: currentSemester,
          unitNumber,
          unitTitle: titlePart,
          unitTitleUrdu,
          description: null,
          sourceDocumentId,
          sourcePage: page,
          sourceUrl,
          version: 1,
          needsVerification: true,
        });
      }
    }
  }

  const subjects: SubjectRow[] = Array.from(subjectGradeMap.entries()).map(([subjectId, grades], i) => ({
    subjectId,
    name: subjectDisplayName(subjectId),
    nameUrdu: null,
    gradeIds: Array.from(grades).sort(),
    sortOrder: i,
    active: true,
  }));

  return { curriculum, subjects };
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

  let pages: PageText[];
  try {
    pages = await extractPages(buffer);
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
  const totalChars = pages.reduce((sum, p) => sum + p.text.length, 0);

  if (args.debug) {
    console.log('');
    console.log('--debug: raw per-page extracted text (before parsing) ---------------');
    for (const p of pages) {
      console.log(`\n----- page ${p.page} -----`);
      console.log(p.text);
    }
    console.log('------------------------------------------------------------------');
    console.log('');
  }

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

  console.log('');
  console.log('Extraction summary');
  console.log('-------------------');
  console.log(`Pages processed:       ${pages.length}`);
  console.log(`Session detected:      ${session}${args.session ? '' : ' (auto-detected — pass --session=YYYY-YY to override)'}`);
  console.log(`Subjects discovered:   ${subjects.length}`);
  console.log(`Curriculum units found:${curriculum.length}`);
  console.log(`Units with Urdu text:  ${curriculum.filter((c) => c.unitTitleUrdu).length}`);
  console.log('All rows are written with needsVerification: true — review before flipping to false.');
  console.log('');

  if (curriculum.length === 0) {
    console.error(
      'Text was extracted but no "Unit N: ..." / "Grade ..." / "Semester ..." patterns were ' +
        'matched. The notification may use different wording than expected — inspect the raw ' +
        'text (re-run with --dry-run and add console.log(pages) locally, or open the PDF ' +
        'directly) and adjust GRADE_PATTERNS / SUBJECT_PATTERNS / UNIT_RE in this script. ' +
        'Nothing was written.',
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
  console.log(`Wrote ${curriculum.length} curriculum units to ${curriculumPath}`);
  console.log('');
  console.log('Next: review both files by hand against the PDF, then run `npm run seed`.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

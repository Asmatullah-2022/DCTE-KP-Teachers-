// pdf-parse has no bundled types with a default export signature matching
// modern TS; require() keeps this robust across versions.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const pdfParse = require('pdf-parse');

export interface PdfExtractionResult {
  rawText: string;
  pageCount: number;
}

/** Extract raw text + page count from a PDF buffer. Never modifies the source. */
export async function extractPdfText(buffer: Buffer): Promise<PdfExtractionResult> {
  const data = await pdfParse(buffer);
  return { rawText: data.text as string, pageCount: data.numpages as number };
}

export interface CurriculumUnitCandidate {
  grade?: string;
  subject?: string;
  semester?: string;
  unitNumber?: number;
  unitTitle?: string;
  page?: number;
  session?: string;
  needsVerification: boolean;
}

/**
 * Best-effort structural extraction for curriculum notification PDFs.
 *
 * This is intentionally conservative: it looks for lines matching common
 * "Unit <n>: <title>" / "Semester I" / "Grade <n>" patterns and always
 * flags results with `needsVerification: true`. Per the accuracy rule, it
 * NEVER invents a title it could not read, and NEVER "corrects" text based
 * on general knowledge — uncertain rows are surfaced to the admin review
 * queue rather than silently guessed. Urdu text is preserved verbatim
 * where detected; if OCR/parsing confidence is low, the row is still
 * created with needsVerification=true rather than dropped, so the original
 * PDF stays discoverable and reviewable.
 */
export function extractCurriculumCandidates(rawText: string): CurriculumUnitCandidate[] {
  const lines = rawText.split('\n').map((l) => l.trim()).filter(Boolean);
  const candidates: CurriculumUnitCandidate[] = [];

  let currentGrade: string | undefined;
  let currentSemester: string | undefined;

  const gradeRe = /\b(ECE|Grade\s?(I{1,3}|IV|V|VI{0,3}|VIII|[1-8]))\b/i;
  const semesterRe = /Semester\s?(I{1,2})\b/i;
  const unitRe = /Unit\s?(\d+)\s*[:\-]\s*(.+)/i;

  for (const line of lines) {
    const gradeMatch = line.match(gradeRe);
    if (gradeMatch) currentGrade = gradeMatch[0];

    const semesterMatch = line.match(semesterRe);
    if (semesterMatch) currentSemester = `Semester ${semesterMatch[1]}`;

    const unitMatch = line.match(unitRe);
    if (unitMatch) {
      candidates.push({
        grade: currentGrade,
        semester: currentSemester,
        unitNumber: parseInt(unitMatch[1], 10),
        unitTitle: unitMatch[2].trim(),
        needsVerification: true,
      });
    }
  }

  return candidates;
}

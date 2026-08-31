/**
 * Best-effort, keyword-based category classification for a detected
 * document/notification title. This is a rough starting tag, not a
 * verified fact — every document still requires human review before
 * publishing (see admin/adminApi.ts `approveDocument`, which accepts
 * `editedMetadata` to correct it), so a wrong guess here costs nothing
 * more than an admin picking the right category during review.
 */
const CATEGORY_KEYWORDS: Array<{ category: string; re: RegExp }> = [
  { category: 'curriculum', re: /curriculum|scheme\s+of\s+studies|syllabus|course\b/i },
  { category: 'assessment', re: /assessment|examination|exam\b|result|date\s*sheet/i },
  { category: 'teacherTraining', re: /training|professional\s+development|workshop/i },
  { category: 'academicCalendar', re: /academic\s+calendar|semester|admission|school\s+calendar/i },
  { category: 'policy', re: /policy|circular|sro\b/i },
];

export function classifyCategory(title: string): string {
  for (const { category, re } of CATEGORY_KEYWORDS) {
    if (re.test(title)) return category;
  }
  return 'notification';
}

/**
 * Loosely parse a scraped date string (e.g. "August 29, 2025", "29-08-2025")
 * into a Date, returning null rather than guessing when it can't be parsed
 * confidently — an unparsed `publishedDate` is left null upstream and an
 * admin fills it in during review, per the "never silently guess" rule.
 */
export function parseLooseDate(text: string | undefined): Date | null {
  if (!text) return null;
  const cleaned = text.trim();
  if (!cleaned) return null;

  const isoLike = cleaned.match(/(\d{4})[-/](\d{1,2})[-/](\d{1,2})/);
  if (isoLike) {
    const d = new Date(Date.UTC(Number(isoLike[1]), Number(isoLike[2]) - 1, Number(isoLike[3])));
    if (!isNaN(d.getTime())) return d;
  }

  const dmy = cleaned.match(/(\d{1,2})[-/](\d{1,2})[-/](\d{4})/);
  if (dmy) {
    const d = new Date(Date.UTC(Number(dmy[3]), Number(dmy[2]) - 1, Number(dmy[1])));
    if (!isNaN(d.getTime())) return d;
  }

  const parsed = new Date(cleaned);
  if (!isNaN(parsed.getTime())) return parsed;

  return null;
}

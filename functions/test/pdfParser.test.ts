import { extractCurriculumCandidates } from '../src/parsers/pdfParser';

describe('extractCurriculumCandidates', () => {
  it('extracts unit candidates and always flags needsVerification', () => {
    const text = [
      'Grade 5',
      'Semester I',
      'Unit 1: Numbers and Operations',
      'Unit 2: Fractions and Decimals',
      'Semester II',
      'Unit 1: Geometry',
    ].join('\n');

    const candidates = extractCurriculumCandidates(text);

    expect(candidates).toHaveLength(3);
    expect(candidates[0]).toMatchObject({
      grade: 'Grade 5',
      semester: 'Semester I',
      unitNumber: 1,
      unitTitle: 'Numbers and Operations',
      needsVerification: true,
    });
    expect(candidates[2].semester).toBe('Semester II');
    expect(candidates.every((c) => c.needsVerification)).toBe(true);
  });

  it('returns an empty array for text with no recognizable units', () => {
    expect(extractCurriculumCandidates('Just some unrelated text.')).toEqual([]);
  });
});

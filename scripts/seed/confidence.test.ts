import { validateRecord, classifyConfidence, findDuplicateKeys, isOcrSuspect, ClassifiableRecord } from './confidence';

const GRADE_IDS = new Set(['grade-5']);
const SUBJECT_IDS = new Set(['mathematics', 'urdu']);
const DOCUMENT_IDS = new Set(['dcte-semester-notification-2025-26']);

function baseRecord(overrides: Partial<ClassifiableRecord> = {}): ClassifiableRecord {
  return {
    curriculumId: 'grade-5-mathematics-semester-i-unit-1',
    gradeId: 'grade-5',
    subjectId: 'mathematics',
    semester: 'Semester I',
    unitNumber: 1,
    unitTitle: 'Real Numbers',
    unitTitleUrdu: null,
    sourcePage: 22,
    sourceDocumentId: 'dcte-semester-notification-2025-26',
    sourceUrl: 'https://dcte.kpese.gov.pk/wp-content/uploads/notice.pdf',
    ...overrides,
  };
}

describe('validateRecord', () => {
  it('passes a clean, well-formed English record', () => {
    const r = baseRecord();
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(v.passed).toBe(true);
    expect(v.issues).toEqual([]);
  });

  it('fails on an unknown gradeId', () => {
    const r = baseRecord({ gradeId: 'grade-99' });
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(v.gradeExists).toBe(false);
    expect(v.passed).toBe(false);
    expect(v.issues.some((i) => i.includes('gradeId'))).toBe(true);
  });

  it('fails on an unknown subjectId', () => {
    const r = baseRecord({ subjectId: 'nonexistent' });
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(v.subjectExists).toBe(false);
    expect(v.passed).toBe(false);
  });

  it('fails on an invalid semester', () => {
    const r = baseRecord({ semester: 'Semester III' });
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(v.semesterValid).toBe(false);
    expect(v.passed).toBe(false);
  });

  it('fails on a missing/invalid sourcePage', () => {
    expect(validateRecord(baseRecord({ sourcePage: null }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
    expect(validateRecord(baseRecord({ sourcePage: 0 }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
    expect(validateRecord(baseRecord({ sourcePage: -3 }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
  });

  it('fails on an unknown sourceDocumentId', () => {
    const r = baseRecord({ sourceDocumentId: 'some-other-doc' });
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(v.sourceDocumentIdExists).toBe(false);
    expect(v.passed).toBe(false);
  });

  it('fails on a missing/malformed sourceUrl', () => {
    expect(validateRecord(baseRecord({ sourceUrl: '' }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
    expect(validateRecord(baseRecord({ sourceUrl: 'not-a-url' }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
  });

  it('fails on an empty unit title', () => {
    expect(validateRecord(baseRecord({ unitTitle: '' }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
    expect(validateRecord(baseRecord({ unitTitle: '   ' }), GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set()).passed).toBe(false);
  });

  it('flags a record whose key is in the duplicate set', () => {
    const r = baseRecord();
    const dupKey = `${r.gradeId}|${r.subjectId}|${r.semester}|${r.unitNumber}`;
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set([dupKey]));
    expect(v.isDuplicate).toBe(true);
    expect(v.passed).toBe(false);
  });
});

describe('isOcrSuspect', () => {
  it('is false for clean English text', () => {
    expect(isOcrSuspect('Real Numbers')).toBe(false);
  });

  it('is false for clean, short Urdu text', () => {
    expect(isOcrSuspect('اخلاق و آداب')).toBe(false);
  });

  it('is true for text dominated by isolated single-character Arabic-script fragments', () => {
    const scrambled = 'م ل س و ہ ٖ ب ِ ا ح َ ص َ ا و ہ ٖ ِ ل ا ّٰ ی ّٰ ل َ';
    expect(isOcrSuspect(scrambled)).toBe(true);
  });

  it('is false for non-Urdu text regardless of shape', () => {
    expect(isOcrSuspect('a b c d e f g h i j k l m n o p')).toBe(false);
  });
});

describe('classifyConfidence', () => {
  const pass = (overrides: Partial<ClassifiableRecord> = {}) => {
    const r = baseRecord(overrides);
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    return { r, v };
  };

  it('classifies a clean English record as HIGH', () => {
    const { r, v } = pass();
    expect(classifyConfidence(r, v)).toBe('HIGH');
  });

  it('never classifies Urdu-containing text as HIGH, even when clean', () => {
    const { r, v } = pass({ unitTitle: 'اخلاق و آداب', subjectId: 'urdu' });
    expect(classifyConfidence(r, v)).toBe('MEDIUM');
  });

  it('classifies OCR-suspect Urdu text as LOW, not MEDIUM', () => {
    const scrambled = 'م ل س و ہ ٖ ب ِ ا ح َ ص َ ا و ہ ٖ ِ ل ا ّٰ ی ّٰ ل َ';
    const { r, v } = pass({ unitTitle: scrambled, subjectId: 'urdu' });
    expect(classifyConfidence(r, v)).toBe('LOW');
  });

  it('classifies a record that fails hard validation as LOW', () => {
    const r = baseRecord({ gradeId: 'unknown-grade' });
    const v = validateRecord(r, GRADE_IDS, SUBJECT_IDS, DOCUMENT_IDS, new Set());
    expect(classifyConfidence(r, v)).toBe('LOW');
  });

  it('classifies a scope-note record (unitNumber 0) as LOW even if otherwise clean', () => {
    const { r, v } = pass({ unitNumber: 0, unitTitle: 'Page No. 1 to 18' });
    expect(classifyConfidence(r, v)).toBe('LOW');
  });
});

describe('findDuplicateKeys', () => {
  it('finds a real duplicate (same grade/subject/semester/unitNumber twice)', () => {
    const records = [baseRecord(), baseRecord({ curriculumId: 'dup' })];
    const dups = findDuplicateKeys(records);
    expect(dups.size).toBe(1);
  });

  it('does not flag two different scope-note records (unitNumber 0) in the same subject/semester as duplicates', () => {
    const records = [
      baseRecord({ unitNumber: 0, unitTitle: 'Page No. 1 to 18' }),
      baseRecord({ unitNumber: 0, unitTitle: 'Page No. 19 to 41', curriculumId: 'other' }),
    ];
    expect(findDuplicateKeys(records).size).toBe(0);
  });

  it('does not flag distinct unit numbers as duplicates', () => {
    const records = [baseRecord({ unitNumber: 1 }), baseRecord({ unitNumber: 2, curriculumId: 'unit-2' })];
    expect(findDuplicateKeys(records).size).toBe(0);
  });
});

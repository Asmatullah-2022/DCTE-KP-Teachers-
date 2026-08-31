import { classifyCategory, parseLooseDate } from '../src/parsers/classify';

describe('classifyCategory', () => {
  it('recognizes an assessment-related title', () => {
    expect(classifyCategory('Date Sheet for Semester-I Examination 2025')).toBe('assessment');
  });

  it('recognizes an academic calendar title', () => {
    expect(classifyCategory('Revised Academic Calendar Notification')).toBe('academicCalendar');
  });

  it('falls back to notification for an unrecognized title', () => {
    expect(classifyCategory('Some Unrelated Announcement')).toBe('notification');
  });
});

describe('parseLooseDate', () => {
  it('parses an ISO-like date', () => {
    const d = parseLooseDate('2025-09-04');
    expect(d?.getUTCFullYear()).toBe(2025);
    expect(d?.getUTCMonth()).toBe(8);
    expect(d?.getUTCDate()).toBe(4);
  });

  it('parses a DD-MM-YYYY date', () => {
    const d = parseLooseDate('04/09/2025');
    expect(d?.getUTCFullYear()).toBe(2025);
    expect(d?.getUTCMonth()).toBe(8);
    expect(d?.getUTCDate()).toBe(4);
  });

  it('returns null rather than guessing for unparseable text', () => {
    expect(parseLooseDate('sometime soon')).toBeNull();
    expect(parseLooseDate(undefined)).toBeNull();
    expect(parseLooseDate('')).toBeNull();
  });
});

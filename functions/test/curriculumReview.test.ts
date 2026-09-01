import { DocumentSnapshot } from 'firebase-admin/firestore';
import { buildApprovalWrites } from '../src/admin/curriculumReview';

function fakeSnap(id: string, data: Record<string, unknown>): DocumentSnapshot {
  return { id, data: () => data } as unknown as DocumentSnapshot;
}

describe('buildApprovalWrites', () => {
  const pendingData = {
    gradeId: 'grade-5',
    subjectId: 'mathematics',
    semester: 'Semester I',
    unitNumber: 1,
    unitTitle: 'Real Numbers',
    unitTitleUrdu: null,
    extractionConfidence: 'HIGH',
    verificationStatus: 'pending_review',
    sourcePage: 22,
    sourceUrl: 'https://dcte.kpese.gov.pk/wp-content/uploads/notice.pdf',
  };

  it('copies the pending record into a public curriculum doc with needsVerification false', () => {
    const snap = fakeSnap('grade-5-mathematics-semester-i-unit-1', pendingData);
    const { publicId, publicData } = buildApprovalWrites(snap, 'admin-uid-1', undefined);

    expect(publicId).toBe(snap.id);
    expect(publicData.needsVerification).toBe(false);
    expect(publicData.unitTitle).toBe('Real Numbers');
    expect(publicData.verificationStatus).toBe('verified');
    expect(publicData.reviewedBy).toBe('admin-uid-1');
    expect(publicData.gradeId).toBe('grade-5'); // original fields carried through
  });

  it('marks the pending doc verified without deleting anything (caller is expected to update, not delete)', () => {
    const snap = fakeSnap('id-1', pendingData);
    const { pendingUpdate } = buildApprovalWrites(snap, 'admin-uid-1', undefined);

    expect(pendingUpdate.verificationStatus).toBe('verified');
    expect(pendingUpdate.reviewedBy).toBe('admin-uid-1');
    expect(pendingUpdate.reviewedAt).toBeDefined();
  });

  it('leaves unitTitle unmodified and records no correction when no editedFields are given', () => {
    const snap = fakeSnap('id-1', pendingData);
    const { publicData } = buildApprovalWrites(snap, 'admin-uid-1', undefined);

    expect(publicData.unitTitle).toBe('Real Numbers');
    expect(publicData.correctedValue).toBeUndefined();
    expect(publicData.originalExtractedValue).toBeUndefined();
  });

  it('applies an edit as a correction, preserving the original extracted value', () => {
    const snap = fakeSnap('id-1', pendingData);
    const { publicData, pendingUpdate } = buildApprovalWrites(snap, 'admin-uid-2', { unitTitle: 'Real Numbers (corrected)' });

    // The corrected text is what's shown publicly...
    expect(publicData.unitTitle).toBe('Real Numbers (corrected)');
    // ...but the original extracted value is preserved for audit.
    expect(publicData.originalExtractedValue).toEqual({ unitTitle: 'Real Numbers', unitTitleUrdu: null });
    expect(publicData.correctedValue).toEqual({ unitTitle: 'Real Numbers (corrected)', unitTitleUrdu: null });
    expect(publicData.correctedBy).toBe('admin-uid-2');

    // The pending audit copy carries the same correction trail.
    expect(pendingUpdate.correctedValue).toEqual({ unitTitle: 'Real Numbers (corrected)', unitTitleUrdu: null });
    expect(pendingUpdate.originalExtractedValue).toEqual({ unitTitle: 'Real Numbers', unitTitleUrdu: null });
  });

  it('never mutates the fields captured at extraction time (rawText/extractedText untouched by approval)', () => {
    const snap = fakeSnap('id-1', {
      ...pendingData,
      rawText: 'Real Numbers',
      extractedText: 'Real Numbers',
    });
    const { publicData } = buildApprovalWrites(snap, 'admin-uid-1', { unitTitle: 'Edited Title' });

    expect(publicData.rawText).toBe('Real Numbers');
    expect(publicData.extractedText).toBe('Real Numbers');
  });
});

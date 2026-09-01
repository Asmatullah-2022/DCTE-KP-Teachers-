import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { checkOfficialSources, forceSyncSource } from './sync/checkOfficialSources';
export {
  getPendingDocuments,
  approveDocument,
  rejectDocument,
  publishNotification,
  setSourceActive,
} from './admin/adminApi';
export {
  getPendingCurriculum,
  approveCurriculumRecord,
  editCurriculumPending,
  rejectCurriculumRecord,
  approveSelectedCurriculum,
  rejectSelectedCurriculum,
  bulkApproveHighConfidence,
  getCurriculumReviewSummary,
  exportCurriculumReviewReport,
} from './admin/curriculumReview';
export { askAssistant } from './ai/extract';

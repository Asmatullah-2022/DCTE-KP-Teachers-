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
export { askAssistant } from './ai/extract';

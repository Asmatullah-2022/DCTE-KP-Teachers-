import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { checkOfficialSources, forceSyncSource } from './sync/checkOfficialSources';
export { approveDocument, rejectDocument, publishNotification, setSourceActive } from './admin/adminApi';
export { askAssistant } from './ai/extract';

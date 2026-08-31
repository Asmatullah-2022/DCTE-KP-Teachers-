import { getFirestore, FieldValue } from 'firebase-admin/firestore';

export interface SyncLogHandle {
  syncId: string;
  finish: (status: 'success' | 'partial' | 'failed', counts: SyncCounts, errors: string[]) => Promise<void>;
}

export interface SyncCounts {
  documentsFound: number;
  documentsAdded: number;
  documentsUpdated: number;
  documentsSkipped: number;
}

export async function startSyncLog(sourceId: string): Promise<SyncLogHandle> {
  const db = getFirestore();
  const ref = await db.collection('sync_logs').add({
    sourceId,
    startedAt: FieldValue.serverTimestamp(),
    completedAt: null,
    status: 'running',
    documentsFound: 0,
    documentsAdded: 0,
    documentsUpdated: 0,
    documentsSkipped: 0,
    errors: [],
  });

  return {
    syncId: ref.id,
    finish: async (status, counts, errors) => {
      await ref.update({
        completedAt: FieldValue.serverTimestamp(),
        status,
        ...counts,
        errors,
      });
    },
  };
}

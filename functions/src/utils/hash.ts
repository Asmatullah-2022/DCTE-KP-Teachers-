import { createHash } from 'crypto';

/** SHA-256 hash of a document's raw bytes, used to detect changed PDFs. */
export function sha256(buffer: Buffer): string {
  return createHash('sha256').update(buffer).digest('hex');
}

import { getFirestore } from 'firebase-admin/firestore';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';

/**
 * AI API key lives ONLY here (Secret Manager via defineSecret), never in
 * the Flutter client. Set it with:
 *   firebase functions:secrets:set AI_API_KEY
 *
 * `askAssistant` is a stub in this MVP: it does a simple keyword lookup
 * against indexed `curriculum` / `documents` / `notifications` and returns
 * the best match with its source document/page, WITHOUT calling an actual
 * LLM. This keeps the architecture ready (secret wiring, callable shape,
 * response format with sourceDocumentTitle/sourcePage) for a real model
 * call to be added later, without ever fabricating an answer today.
 */
export const aiApiKey = defineSecret('AI_API_KEY');

export const askAssistant = onCall({ secrets: [aiApiKey] }, async (request) => {
  const question = (request.data?.question as string | undefined)?.trim();
  if (!question) {
    throw new HttpsError('invalid-argument', 'question is required.');
  }

  const db = getFirestore();
  const token = question.toLowerCase().split(/\s+/).find((t) => t.length > 3) ?? '';

  if (token) {
    const curriculumSnap = await db
      .collection('curriculum')
      .where('searchKeywords', 'array-contains', token)
      .limit(1)
      .get();

    if (!curriculumSnap.empty) {
      const unit = curriculumSnap.docs[0].data();
      return {
        answer: `${unit.unitTitle} (Unit ${unit.unitNumber}, ${unit.semester}).`,
        sourceDocumentTitle: unit.sourceDocumentId ?? unit.sourceUrl,
        sourcePage: unit.sourcePage ?? null,
      };
    }

    const notifSnap = await db
      .collection('notifications')
      .where('searchKeywords', 'array-contains', token)
      .where('isVerified', '==', true)
      .limit(1)
      .get();

    if (!notifSnap.empty) {
      const n = notifSnap.docs[0].data();
      return {
        answer: n.summary ?? n.title,
        sourceDocumentTitle: n.title,
        sourcePage: null,
      };
    }
  }

  return {
    answer:
      'I could not find an indexed official document that answers this confidently. ' +
      'Please check the Curriculum or Documents section, or refine your question.',
    sourceDocumentTitle: null,
    sourcePage: null,
  };
});

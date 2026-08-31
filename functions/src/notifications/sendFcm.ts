import { getMessaging } from 'firebase-admin/messaging';
import { logger } from 'firebase-functions/v2';

const CATEGORY_TOPIC: Record<string, string> = {
  curriculum: 'dcte_curriculum',
  schemeOfStudies: 'dcte_curriculum',
  assessment: 'dcte_assessment',
  examination: 'dcte_assessment',
  teacherTraining: 'dcte_teacher_training',
  academicCalendar: 'dcte_academic',
  policy: 'dcte_notifications',
  notification: 'dcte_notifications',
  other: 'dcte_notifications',
};

/**
 * Sends an FCM push for a just-published notification to the "all"
 * topic plus its category-specific topic, so users who opted out of a
 * category (but kept "All Updates" on) still get relevant pushes exactly
 * once via topic de-duplication on the client subscription state.
 */
export async function sendNotificationPush(params: {
  notificationId: string;
  title: string;
  summary?: string;
  category: string;
}): Promise<void> {
  const categoryTopic = CATEGORY_TOPIC[params.category] ?? 'dcte_notifications';
  const messaging = getMessaging();

  const base = {
    notification: {
      title: params.title,
      body: params.summary ?? 'Tap to view the official update.',
    },
    data: {
      notificationId: params.notificationId,
      category: params.category,
    },
  };

  try {
    await messaging.send({ ...base, topic: 'dcte_all' });
  } catch (err) {
    logger.error('Failed to send to dcte_all', err);
  }

  try {
    await messaging.send({ ...base, topic: categoryTopic });
  } catch (err) {
    logger.error(`Failed to send to ${categoryTopic}`, err);
  }
}

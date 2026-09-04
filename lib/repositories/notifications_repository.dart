import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/firestore_error_logger.dart';
import '../models/notification_model.dart';

class NotificationsRepository {
  final FirebaseFirestore _db;
  NotificationsRepository(this._db);

  /// Only verified/published notifications are readable by public users
  /// per firestore.rules; this query mirrors that intent client-side too.
  ///
  /// Unlike Curriculum/Academic Calendar, there is no legitimate offline
  /// fallback content here — announcements are inherently live, so a bundled
  /// "fallback" would just be stale or fabricated. Errors are logged for
  /// diagnosis and rethrown so the UI's error state stays honest.
  Stream<List<NotificationModel>> watchFeed({NotificationCategory? category, int limit = 50}) async* {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.collectionNotifications)
        .where('isVerified', isEqualTo: true);
    if (category != null) {
      q = q.where('category', isEqualTo: category.name);
    }
    q = q.orderBy('publishedDate', descending: true).limit(limit);
    try {
      yield* q.snapshots().map((s) => s.docs.map(NotificationModel.fromDoc).toList());
    } catch (e, st) {
      logFirestoreError('NotificationsRepository.watchFeed', e, st);
      rethrow;
    }
  }
}

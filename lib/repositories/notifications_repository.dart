import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/notification_model.dart';

class NotificationsRepository {
  final FirebaseFirestore _db;
  NotificationsRepository(this._db);

  /// Only verified/published notifications are readable by public users
  /// per firestore.rules; this query mirrors that intent client-side too.
  Stream<List<NotificationModel>> watchFeed({NotificationCategory? category, int limit = 50}) {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.collectionNotifications)
        .where('isVerified', isEqualTo: true);
    if (category != null) {
      q = q.where('category', isEqualTo: category.name);
    }
    q = q.orderBy('publishedDate', descending: true).limit(limit);
    return q.snapshots().map((s) => s.docs.map(NotificationModel.fromDoc).toList());
  }
}

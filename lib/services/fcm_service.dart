import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

/// Handles POST_NOTIFICATIONS permission (Android 13+), FCM topic
/// subscriptions, and per-category user preference persistence.
class FcmService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static const _prefKeyPrefix = 'fcm_topic_enabled_';

  Future<void> requestPermission() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  Future<bool> isTopicEnabled(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    // Default: dcte_all is on by default; others follow user choice, default true.
    return prefs.getBool('$_prefKeyPrefix$topic') ?? true;
  }

  Future<void> setTopicEnabled(String topic, bool enabled) async {
    if (!AppConstants.fcmTopics.contains(topic)) {
      throw ArgumentError('Unknown FCM topic: $topic');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefKeyPrefix$topic', enabled);
    if (enabled) {
      await _messaging.subscribeToTopic(topic);
    } else {
      await _messaging.unsubscribeFromTopic(topic);
    }
  }

  Future<void> applyStoredSubscriptions() async {
    for (final topic in AppConstants.fcmTopics) {
      final enabled = await isTopicEnabled(topic);
      if (enabled) {
        await _messaging.subscribeToTopic(topic);
      }
    }
  }

  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;
}

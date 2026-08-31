import 'package:cloud_firestore/cloud_firestore.dart';

/// Singleton-ish config docs read from `app_config/{docId}`.
/// Known doc: `app_config/global` -> { lastSyncedAt, currentSession, minAppVersion }
class AppConfigModel {
  final DateTime? lastSyncedAt;
  final String? currentSession;
  final String? minSupportedVersion;

  const AppConfigModel({this.lastSyncedAt, this.currentSession, this.minSupportedVersion});

  factory AppConfigModel.fromMap(Map<String, dynamic> map) => AppConfigModel(
        lastSyncedAt: (map['lastSyncedAt'] as Timestamp?)?.toDate(),
        currentSession: map['currentSession'] as String?,
        minSupportedVersion: map['minSupportedVersion'] as String?,
      );

  factory AppConfigModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppConfigModel.fromMap(doc.data() ?? const {});
}

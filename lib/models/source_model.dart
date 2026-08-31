import 'package:cloud_firestore/cloud_firestore.dart';

class SourceModel {
  final String sourceId;
  final String name;
  final String baseUrl;
  final String sourceType; // 'html' | 'pdf' | 'rss'
  final bool active;
  final DateTime? lastCheckedAt;
  final DateTime? lastSuccessfulCheckAt;
  final String checkFrequency; // cron-like description, e.g. "daily"

  const SourceModel({
    required this.sourceId,
    required this.name,
    required this.baseUrl,
    required this.sourceType,
    required this.active,
    this.lastCheckedAt,
    this.lastSuccessfulCheckAt,
    required this.checkFrequency,
  });

  factory SourceModel.fromMap(String id, Map<String, dynamic> map) {
    return SourceModel(
      sourceId: id,
      name: map['name'] as String? ?? id,
      baseUrl: map['baseUrl'] as String? ?? '',
      sourceType: map['sourceType'] as String? ?? 'html',
      active: map['active'] as bool? ?? true,
      lastCheckedAt: (map['lastCheckedAt'] as Timestamp?)?.toDate(),
      lastSuccessfulCheckAt: (map['lastSuccessfulCheckAt'] as Timestamp?)?.toDate(),
      checkFrequency: map['checkFrequency'] as String? ?? 'daily',
    );
  }

  factory SourceModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      SourceModel.fromMap(doc.id, doc.data() ?? const {});
}

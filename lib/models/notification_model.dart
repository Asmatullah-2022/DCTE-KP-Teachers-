import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

class NotificationModel {
  final String notificationId;
  final String title;
  final String? titleUrdu;
  final NotificationCategory category;
  final String department;
  final DateTime? publishedDate;
  final String? notificationNumber;
  final String? description;
  final String? summary;
  final String sourceUrl;
  final String? documentId;
  final bool isNew;
  final bool isVerified;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const NotificationModel({
    required this.notificationId,
    required this.title,
    this.titleUrdu,
    required this.category,
    required this.department,
    this.publishedDate,
    this.notificationNumber,
    this.description,
    this.summary,
    required this.sourceUrl,
    this.documentId,
    this.isNew = false,
    this.isVerified = false,
    this.createdAt,
    this.updatedAt,
  });

  factory NotificationModel.fromMap(String id, Map<String, dynamic> map) {
    return NotificationModel(
      notificationId: id,
      title: map['title'] as String? ?? '',
      titleUrdu: map['titleUrdu'] as String?,
      category: NotificationCategoryX.fromString(map['category'] as String?),
      department: map['department'] as String? ?? '',
      publishedDate: (map['publishedDate'] as Timestamp?)?.toDate(),
      notificationNumber: map['notificationNumber'] as String?,
      description: map['description'] as String?,
      summary: map['summary'] as String?,
      sourceUrl: map['sourceUrl'] as String? ?? '',
      documentId: map['documentId'] as String?,
      isNew: map['isNew'] as bool? ?? false,
      isVerified: map['isVerified'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory NotificationModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      NotificationModel.fromMap(doc.id, doc.data() ?? const {});
}

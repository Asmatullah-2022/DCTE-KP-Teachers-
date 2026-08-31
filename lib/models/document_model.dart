import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentStatus { detected, downloaded, extracted, pendingReview, verified, published, rejected }

DocumentStatus documentStatusFromString(String? value) {
  return DocumentStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DocumentStatus.pendingReview,
  );
}

class DocumentModel {
  final String documentId;
  final String title;
  final String? titleUrdu;
  final String documentType;
  final String department;
  final DateTime? publishedDate;
  final String? notificationNumber;
  final String sourceUrl;
  final String? storageUrl;
  final String? fileHash;
  final int? fileSize;
  final int? pageCount;
  final String? summary;
  final String? aiSummary;
  final DocumentStatus status;
  final bool verified;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DocumentModel({
    required this.documentId,
    required this.title,
    this.titleUrdu,
    required this.documentType,
    required this.department,
    this.publishedDate,
    this.notificationNumber,
    required this.sourceUrl,
    this.storageUrl,
    this.fileHash,
    this.fileSize,
    this.pageCount,
    this.summary,
    this.aiSummary,
    this.status = DocumentStatus.pendingReview,
    this.verified = false,
    this.createdAt,
    this.updatedAt,
  });

  factory DocumentModel.fromMap(String id, Map<String, dynamic> map) {
    return DocumentModel(
      documentId: id,
      title: map['title'] as String? ?? '',
      titleUrdu: map['titleUrdu'] as String?,
      documentType: map['documentType'] as String? ?? 'Notification',
      department: map['department'] as String? ?? '',
      publishedDate: (map['publishedDate'] as Timestamp?)?.toDate(),
      notificationNumber: map['notificationNumber'] as String?,
      sourceUrl: map['sourceUrl'] as String? ?? '',
      storageUrl: map['storageUrl'] as String?,
      fileHash: map['fileHash'] as String?,
      fileSize: (map['fileSize'] as num?)?.toInt(),
      pageCount: (map['pageCount'] as num?)?.toInt(),
      summary: map['summary'] as String?,
      aiSummary: map['aiSummary'] as String?,
      status: documentStatusFromString(map['status'] as String?),
      verified: map['verified'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory DocumentModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      DocumentModel.fromMap(doc.id, doc.data() ?? const {});
}

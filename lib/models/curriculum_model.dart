import 'package:cloud_firestore/cloud_firestore.dart';

/// Grade -> Subject -> Semester -> Unit, extracted from official notifications.
/// `needsVerification` MUST be true whenever automated/AI extraction could
/// not confidently read the original (e.g. Urdu OCR uncertainty) — the raw
/// source document/page must remain the source of truth until an admin
/// verifies and clears the flag.
class CurriculumModel {
  final String curriculumId;
  final String gradeId;
  final String subjectId;
  final String session;
  final String semester; // 'Semester I' | 'Semester II'
  final int unitNumber;
  final String unitTitle;
  final String? unitTitleUrdu;
  final String? description;
  final String? sourceDocumentId;
  final int? sourcePage;
  final String sourceUrl;
  final int version;
  final bool needsVerification;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CurriculumModel({
    required this.curriculumId,
    required this.gradeId,
    required this.subjectId,
    required this.session,
    required this.semester,
    required this.unitNumber,
    required this.unitTitle,
    this.unitTitleUrdu,
    this.description,
    this.sourceDocumentId,
    this.sourcePage,
    required this.sourceUrl,
    required this.version,
    this.needsVerification = false,
    this.createdAt,
    this.updatedAt,
  });

  factory CurriculumModel.fromMap(String id, Map<String, dynamic> map) {
    return CurriculumModel(
      curriculumId: id,
      gradeId: map['gradeId'] as String? ?? '',
      subjectId: map['subjectId'] as String? ?? '',
      session: map['session'] as String? ?? '',
      semester: map['semester'] as String? ?? '',
      unitNumber: (map['unitNumber'] as num?)?.toInt() ?? 0,
      unitTitle: map['unitTitle'] as String? ?? '',
      unitTitleUrdu: map['unitTitleUrdu'] as String?,
      description: map['description'] as String?,
      sourceDocumentId: map['sourceDocumentId'] as String?,
      sourcePage: (map['sourcePage'] as num?)?.toInt(),
      sourceUrl: map['sourceUrl'] as String? ?? '',
      version: (map['version'] as num?)?.toInt() ?? 1,
      needsVerification: map['needsVerification'] as bool? ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  factory CurriculumModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      CurriculumModel.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'gradeId': gradeId,
        'subjectId': subjectId,
        'session': session,
        'semester': semester,
        'unitNumber': unitNumber,
        'unitTitle': unitTitle,
        'unitTitleUrdu': unitTitleUrdu,
        'description': description,
        'sourceDocumentId': sourceDocumentId,
        'sourcePage': sourcePage,
        'sourceUrl': sourceUrl,
        'version': version,
        'needsVerification': needsVerification,
        'createdAt': createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}

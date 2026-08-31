import 'package:cloud_firestore/cloud_firestore.dart';

class SubjectModel {
  final String subjectId;
  final String name;
  final String? nameUrdu;
  final List<String> gradeIds;
  final int sortOrder;
  final bool active;

  const SubjectModel({
    required this.subjectId,
    required this.name,
    this.nameUrdu,
    required this.gradeIds,
    required this.sortOrder,
    required this.active,
  });

  factory SubjectModel.fromMap(String id, Map<String, dynamic> map) {
    return SubjectModel(
      subjectId: id,
      name: map['name'] as String? ?? id,
      nameUrdu: map['nameUrdu'] as String?,
      gradeIds: (map['gradeIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      active: map['active'] as bool? ?? true,
    );
  }

  factory SubjectModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      SubjectModel.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'name': name,
        'nameUrdu': nameUrdu,
        'gradeIds': gradeIds,
        'sortOrder': sortOrder,
        'active': active,
      };
}

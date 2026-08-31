import 'package:cloud_firestore/cloud_firestore.dart';

class GradeModel {
  final String gradeId;
  final String name;
  final String displayName;
  final int sortOrder;
  final bool active;

  const GradeModel({
    required this.gradeId,
    required this.name,
    required this.displayName,
    required this.sortOrder,
    required this.active,
  });

  factory GradeModel.fromMap(String id, Map<String, dynamic> map) {
    return GradeModel(
      gradeId: id,
      name: map['name'] as String? ?? id,
      displayName: map['displayName'] as String? ?? map['name'] as String? ?? id,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      active: map['active'] as bool? ?? true,
    );
  }

  factory GradeModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      GradeModel.fromMap(doc.id, doc.data() ?? const {});

  Map<String, dynamic> toMap() => {
        'name': name,
        'displayName': displayName,
        'sortOrder': sortOrder,
        'active': active,
      };
}

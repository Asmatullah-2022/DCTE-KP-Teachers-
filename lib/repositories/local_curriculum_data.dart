import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/curriculum_model.dart';
import '../models/grade_model.dart';
import '../models/subject_model.dart';

/// Bundled offline fallback for the Curriculum feature.
///
/// These are the same ECE-to-Grade-VIII records extracted from the official
/// DCTE semester notification (see scripts/seed/), packaged as app assets
/// so Curriculum can show verified data even when Firestore is unreachable
/// (rules/indexes not yet deployed on the live project, no connectivity,
/// etc.) rather than an error screen. This is a fallback source, not a
/// replacement for Firestore — once Firestore returns real data, the
/// repositories above prefer it.
class LocalCurriculumData {
  LocalCurriculumData._();

  static List<GradeModel>? _grades;
  static List<SubjectModel>? _subjects;
  static List<CurriculumModel>? _curriculum;

  static Future<List<GradeModel>> grades() async {
    return _grades ??= await _loadList(
      'assets/data/grades.json',
      (id, map) => GradeModel.fromMap(id, map),
      idField: 'gradeId',
    );
  }

  static Future<List<SubjectModel>> subjects() async {
    return _subjects ??= await _loadList(
      'assets/data/subjects.json',
      (id, map) => SubjectModel.fromMap(id, map),
      idField: 'subjectId',
    );
  }

  static Future<List<CurriculumModel>> curriculum() async {
    return _curriculum ??= await _loadList(
      'assets/data/curriculum.json',
      (id, map) => CurriculumModel.fromMap(id, map),
      idField: 'curriculumId',
    );
  }

  static Future<List<T>> _loadList<T>(
    String assetPath,
    T Function(String id, Map<String, dynamic> map) fromMap, {
    required String idField,
  }) async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      final id = map[idField] as String;
      return fromMap(id, map);
    }).toList();
  }
}

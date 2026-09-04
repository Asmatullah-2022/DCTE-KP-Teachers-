import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/academic_calendar_model.dart';

/// Bundled offline fallback for the Academic Calendar — the same
/// zone/semester dates extracted from the official DCTE semester
/// notification (see scripts/seed/academic_calendar.json), already marked
/// `verified: true` there. Used the same way as LocalCurriculumData: a
/// fallback for when Firestore is unreachable or unseeded, never a
/// replacement once real data is there.
class LocalAcademicCalendarData {
  LocalAcademicCalendarData._();

  static List<AcademicCalendarModel>? _calendar;

  static Future<List<AcademicCalendarModel>> calendar() async {
    if (_calendar != null) return _calendar!;
    final raw = await rootBundle.loadString('assets/data/academic_calendar.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    _calendar = decoded.map((entry) {
      final map = Map<String, dynamic>.from(entry as Map);
      final id = map['calendarId'] as String;
      // The model's fromMap expects Firestore Timestamps; the bundled JSON
      // stores plain ISO date strings, so convert before handing off.
      map['startDate'] = Timestamp.fromDate(DateTime.parse(map['startDate'] as String));
      map['endDate'] = Timestamp.fromDate(DateTime.parse(map['endDate'] as String));
      return AcademicCalendarModel.fromMap(id, map);
    }).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return _calendar!;
  }
}

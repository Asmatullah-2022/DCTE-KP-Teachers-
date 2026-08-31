import '../../models/academic_calendar_model.dart';
import '../constants/app_constants.dart';

/// Pure function: given the academic calendar rows loaded from Firestore
/// (never hard-coded), a zone, and "now", determine which semester is
/// currently active — or null if `now` falls in a gap between semesters.
class SemesterCalculator {
  const SemesterCalculator._();

  static AcademicCalendarModel? currentSemester({
    required List<AcademicCalendarModel> calendar,
    required SemesterZone zone,
    required DateTime now,
  }) {
    final zoneEntries = calendar.where((c) => c.zone == zone).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    for (final entry in zoneEntries) {
      if (entry.containsDate(now)) return entry;
    }
    return null;
  }

  /// Next upcoming semester if `now` is before all/between semesters.
  static AcademicCalendarModel? nextSemester({
    required List<AcademicCalendarModel> calendar,
    required SemesterZone zone,
    required DateTime now,
  }) {
    final zoneEntries = calendar.where((c) => c.zone == zone && c.startDate.isAfter(now)).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return zoneEntries.isEmpty ? null : zoneEntries.first;
  }
}

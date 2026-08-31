import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/core/constants/app_constants.dart';
import 'package:dcte_kp_teachers/core/utils/semester_calculator.dart';
import 'package:dcte_kp_teachers/models/academic_calendar_model.dart';

AcademicCalendarModel _row({
  required String id,
  required SemesterZone zone,
  required Semester semester,
  required DateTime start,
  required DateTime end,
}) {
  return AcademicCalendarModel(
    calendarId: id,
    session: '2025-26',
    zone: zone,
    semester: semester,
    startDate: start,
    endDate: end,
    label: '$zone $semester',
    verified: true,
  );
}

void main() {
  final calendar = [
    _row(
      id: 'summer-s1',
      zone: SemesterZone.summer,
      semester: Semester.semesterI,
      start: DateTime(2025, 9, 1),
      end: DateTime(2025, 12, 31),
    ),
    _row(
      id: 'summer-s2',
      zone: SemesterZone.summer,
      semester: Semester.semesterII,
      start: DateTime(2026, 1, 16),
      end: DateTime(2026, 5, 31),
    ),
    _row(
      id: 'winter-s1',
      zone: SemesterZone.winter,
      semester: Semester.semesterI,
      start: DateTime(2025, 3, 1),
      end: DateTime(2025, 6, 30),
    ),
    _row(
      id: 'winter-s2',
      zone: SemesterZone.winter,
      semester: Semester.semesterII,
      start: DateTime(2025, 8, 1),
      end: DateTime(2025, 12, 15),
    ),
  ];

  group('SemesterCalculator — Summer zone', () {
    test('returns Semester I mid-way through its window', () {
      final result = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.summer,
        now: DateTime(2025, 10, 15),
      );
      expect(result?.calendarId, 'summer-s1');
    });

    test('returns Semester II mid-way through its window', () {
      final result = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.summer,
        now: DateTime(2026, 3, 1),
      );
      expect(result?.calendarId, 'summer-s2');
    });

    test('returns null in the gap between Semester I and Semester II', () {
      final result = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.summer,
        now: DateTime(2026, 1, 5),
      );
      expect(result, isNull);
    });
  });

  group('SemesterCalculator — Winter zone', () {
    test('returns Semester I mid-way through its window', () {
      final result = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.winter,
        now: DateTime(2025, 4, 1),
      );
      expect(result?.calendarId, 'winter-s1');
    });

    test('returns Semester II mid-way through its window', () {
      final result = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.winter,
        now: DateTime(2025, 9, 1),
      );
      expect(result?.calendarId, 'winter-s2');
    });

    test('boundary dates are inclusive', () {
      final startResult = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.winter,
        now: DateTime(2025, 8, 1),
      );
      final endResult = SemesterCalculator.currentSemester(
        calendar: calendar,
        zone: SemesterZone.winter,
        now: DateTime(2025, 12, 15),
      );
      expect(startResult?.calendarId, 'winter-s2');
      expect(endResult?.calendarId, 'winter-s2');
    });
  });

  test('nextSemester finds the earliest future window for the zone', () {
    final result = SemesterCalculator.nextSemester(
      calendar: calendar,
      zone: SemesterZone.summer,
      now: DateTime(2025, 1, 1),
    );
    expect(result?.calendarId, 'summer-s1');
  });
}

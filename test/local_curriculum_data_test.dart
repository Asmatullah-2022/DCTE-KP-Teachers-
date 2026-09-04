import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/repositories/local_curriculum_data.dart';
import 'package:dcte_kp_teachers/repositories/local_academic_calendar_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled academic calendar asset loads with valid date ranges', () async {
    final calendar = await LocalAcademicCalendarData.calendar();
    expect(calendar, isNotEmpty);
    expect(calendar.every((c) => c.endDate.isAfter(c.startDate)), isTrue);
  });

  test('bundled grades asset loads and covers ECE to Grade 8', () async {
    final grades = await LocalCurriculumData.grades();
    expect(grades, isNotEmpty);
    final ids = grades.map((g) => g.gradeId).toSet();
    expect(ids, contains('ece'));
    expect(ids, contains('grade-8'));
  });

  test('bundled subjects asset loads', () async {
    final subjects = await LocalCurriculumData.subjects();
    expect(subjects, isNotEmpty);
    expect(subjects.every((s) => s.gradeIds.isNotEmpty), isTrue);
  });

  test('bundled curriculum asset loads with valid unit records', () async {
    final units = await LocalCurriculumData.curriculum();
    expect(units, isNotEmpty);
    expect(units.every((u) => u.gradeId.isNotEmpty && u.subjectId.isNotEmpty), isTrue);
  });
}

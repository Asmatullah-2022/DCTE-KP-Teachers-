import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/core/constants/app_constants.dart';
import 'package:dcte_kp_teachers/repositories/local_curriculum_data.dart';
import 'package:dcte_kp_teachers/repositories/local_academic_calendar_data.dart';
import 'package:dcte_kp_teachers/services/curriculum_admin_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('admin email whitelist contains the configured curriculum editor', () {
    expect(AppConstants.adminEmails, contains('asmatullahpst107@gmail.com'));
  });

  test('seed doc IDs are unit_01 through unit_11, zero-padded', () {
    expect(CurriculumAdminService.unitDocId(1), 'unit_01');
    expect(CurriculumAdminService.unitDocId(9), 'unit_09');
    expect(CurriculumAdminService.unitDocId(11), 'unit_11');
  });

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

  test('bundled curriculum has exactly 11 Grade 1 English units with deterministic ids', () async {
    final units = await LocalCurriculumData.curriculum();
    final grade1English = units.where((u) => u.gradeId == 'grade-1' && u.subjectId == 'english').toList()
      ..sort((a, b) => a.unitNumber.compareTo(b.unitNumber));

    expect(grade1English, hasLength(11));
    expect(grade1English.map((u) => u.unitNumber), List.generate(11, (i) => i + 1));
    expect(grade1English.every((u) => u.curriculumId == 'grade-1-english-${u.semester == 'Semester I' ? 'semester-i' : 'semester-ii'}-unit-${u.unitNumber}'), isTrue);
    expect(grade1English.map((u) => u.semester).toSet(), {'Semester I', 'Semester II'});
  });
}

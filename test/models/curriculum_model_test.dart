import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/models/curriculum_model.dart';

void main() {
  group('CurriculumModel.fromMap', () {
    test('parses a fully populated map', () {
      final model = CurriculumModel.fromMap('unit-1', {
        'gradeId': 'grade-5',
        'subjectId': 'mathematics',
        'session': '2025-26',
        'semester': 'Semester I',
        'unitNumber': 1,
        'unitTitle': 'Numbers and Operations',
        'unitTitleUrdu': 'اعداد اور عمل',
        'sourceUrl': 'https://dcte.kpese.gov.pk/wp-content/uploads/notice.pdf',
        'sourcePage': 12,
        'version': 1,
        'needsVerification': false,
      });

      expect(model.curriculumId, 'unit-1');
      expect(model.gradeId, 'grade-5');
      expect(model.unitNumber, 1);
      expect(model.needsVerification, isFalse);
      expect(model.sourcePage, 12);
    });

    test('defaults needsVerification to false and handles missing optional fields', () {
      final model = CurriculumModel.fromMap('unit-2', {
        'gradeId': 'grade-1',
        'subjectId': 'urdu',
        'session': '2025-26',
        'semester': 'Semester II',
        'unitNumber': 3,
        'unitTitle': 'Placeholder',
        'sourceUrl': 'https://dcte.kpese.gov.pk/',
      });

      expect(model.needsVerification, isFalse);
      expect(model.unitTitleUrdu, isNull);
      expect(model.sourcePage, isNull);
      expect(model.version, 1);
    });
  });
}

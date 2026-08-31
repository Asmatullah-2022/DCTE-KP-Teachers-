import 'package:flutter_test/flutter_test.dart';
import 'package:dcte_kp_teachers/core/constants/app_constants.dart';
import 'package:dcte_kp_teachers/models/notification_model.dart';

void main() {
  group('NotificationModel.fromMap', () {
    test('maps a known category string', () {
      final model = NotificationModel.fromMap('n1', {
        'title': 'Scheme of Studies Update',
        'category': 'schemeOfStudies',
        'department': 'DCTE',
        'sourceUrl': 'https://dcte.kpese.gov.pk/',
        'isNew': true,
        'isVerified': true,
      });

      expect(model.category, NotificationCategory.schemeOfStudies);
      expect(model.isNew, isTrue);
      expect(model.isVerified, isTrue);
    });

    test('falls back to "other" for an unknown/missing category', () {
      final model = NotificationModel.fromMap('n2', {
        'title': 'Untitled',
        'department': 'KPESE',
        'sourceUrl': 'https://kpese.gov.pk/',
      });

      expect(model.category, NotificationCategory.other);
      expect(model.isNew, isFalse);
      expect(model.isVerified, isFalse);
    });
  });

  test('AppConstants.fcmTopics carries exactly the six required topics', () {
    expect(AppConstants.fcmTopics, [
      'dcte_all',
      'dcte_curriculum',
      'dcte_notifications',
      'dcte_assessment',
      'dcte_teacher_training',
      'dcte_academic',
    ]);
  });
}

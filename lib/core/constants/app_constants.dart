/// App-wide constants. Values that are content (not just config) live in
/// Firestore (`app_config`, `sources`, `academic_calendar`) so they can be
/// updated without an app release — these are only fallbacks/labels.
class AppConstants {
  AppConstants._();

  static const String appName = 'DCTE KP Teachers';
  static const String appSubtitle =
      'Curriculum • Notifications • Documents • Teacher Resources';

  static const String disclaimer =
      'This is an independent educational information application. '
      'It is not an official government application and is not affiliated '
      'with or endorsed by the Government of Khyber Pakhtunkhwa, DCTE or '
      'KPESE.';

  // Official source URLs — used only for outbound links / attribution.
  // Never scraped from the client; see functions/src/sources for the
  // server-side monitoring implementation.
  static const String dcteBaseUrl = 'https://dcte.kpese.gov.pk/';
  static const String kpeseBaseUrl = 'https://kpese.gov.pk/';
  static const String kpeseNotificationsUrl =
      'https://kpese.gov.pk/category/notifications/';
  static const String dcteSemesterNotificationPdf =
      'https://dcte.kpese.gov.pk/wp-content/uploads/Revised-Notification-Semester-wise-Course-Grade-I-VIII-final-draft.pdf';

  // FCM topics
  static const List<String> fcmTopics = [
    'dcte_all',
    'dcte_curriculum',
    'dcte_notifications',
    'dcte_assessment',
    'dcte_teacher_training',
    'dcte_academic',
  ];

  // Firestore collection names
  static const String collectionGrades = 'grades';
  static const String collectionSubjects = 'subjects';
  static const String collectionCurriculum = 'curriculum';
  static const String collectionDocuments = 'documents';
  static const String collectionNotifications = 'notifications';
  static const String collectionAcademicCalendar = 'academic_calendar';
  static const String collectionSources = 'sources';
  static const String collectionSyncLogs = 'sync_logs';
  static const String collectionUsers = 'users';
  static const String collectionAppConfig = 'app_config';

  // Local (Hive) box names
  static const String boxCache = 'dcte_cache_box';
  static const String boxFavorites = 'dcte_favorites_box';
  static const String boxSettings = 'dcte_settings_box';

  static const String keyLastSyncedAt = 'last_synced_at';
}

enum NotificationCategory {
  curriculum,
  schemeOfStudies,
  assessment,
  examination,
  teacherTraining,
  academicCalendar,
  policy,
  notification,
  other,
}

extension NotificationCategoryX on NotificationCategory {
  String get label {
    switch (this) {
      case NotificationCategory.curriculum:
        return 'Curriculum';
      case NotificationCategory.schemeOfStudies:
        return 'Scheme of Studies';
      case NotificationCategory.assessment:
        return 'Assessment';
      case NotificationCategory.examination:
        return 'Examination';
      case NotificationCategory.teacherTraining:
        return 'Teacher Training';
      case NotificationCategory.academicCalendar:
        return 'Academic Calendar';
      case NotificationCategory.policy:
        return 'Policy';
      case NotificationCategory.notification:
        return 'Notification';
      case NotificationCategory.other:
        return 'Other';
    }
  }

  static NotificationCategory fromString(String? value) {
    return NotificationCategory.values.firstWhere(
      (c) => c.name == value || c.label == value,
      orElse: () => NotificationCategory.other,
    );
  }
}

enum SemesterZone { summer, winter }

enum Semester { semesterI, semesterII }

extension SemesterX on Semester {
  String get label => this == Semester.semesterI ? 'Semester I' : 'Semester II';
}

extension SemesterZoneX on SemesterZone {
  String get label => this == SemesterZone.summer ? 'Summer Zone' : 'Winter Zone';
}

import 'package:go_router/go_router.dart';

import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/home/home_screen.dart';
import '../features/curriculum/curriculum_screen.dart';
import '../features/curriculum/grade_subjects_screen.dart';
import '../features/curriculum/subject_semesters_screen.dart';
import '../features/curriculum/semester_units_screen.dart';
import '../features/curriculum/unit_detail_screen.dart';
import '../features/semester/semester_calendar_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/documents/document_viewer_screen.dart';
import '../features/search/search_screen.dart';
import '../features/resources/resources_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/about_screen.dart';
import '../features/assistant/assistant_screen.dart';
import '../widgets/main_shell.dart';

/// Route paths as constants to avoid typos across the app.
class Routes {
  Routes._();
  static const home = '/';
  static const curriculum = '/curriculum';
  static const gradeSubjects = '/curriculum/:gradeId';
  static const subjectSemesters = '/curriculum/:gradeId/:subjectId';
  static const semesterUnits = '/curriculum/:gradeId/:subjectId/:semester';
  static const unitDetail = '/curriculum/unit/:curriculumId';
  static const semesterCalendar = '/semester-calendar';
  static const notifications = '/notifications';
  static const documents = '/documents';
  static const documentViewer = '/documents/:documentId';
  static const search = '/search';
  static const resources = '/resources';
  static const favorites = '/favorites';
  static const settings = '/settings';
  static const about = '/settings/about';
  static const assistant = '/assistant';
  static const login = '/login';
  static const signUp = '/signup';
  static const forgotPassword = '/forgot-password';
}

final appRouter = GoRouter(
  initialLocation: Routes.home,
  routes: [
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: Routes.home, builder: (context, state) => const HomeScreen()),
        GoRoute(path: Routes.curriculum, builder: (context, state) => const CurriculumScreen()),
        GoRoute(
          path: Routes.gradeSubjects,
          builder: (context, state) => GradeSubjectsScreen(gradeId: state.pathParameters['gradeId']!),
        ),
        GoRoute(
          path: Routes.subjectSemesters,
          builder: (context, state) => SubjectSemestersScreen(
            gradeId: state.pathParameters['gradeId']!,
            subjectId: state.pathParameters['subjectId']!,
          ),
        ),
        GoRoute(
          path: Routes.semesterUnits,
          builder: (context, state) => SemesterUnitsScreen(
            gradeId: state.pathParameters['gradeId']!,
            subjectId: state.pathParameters['subjectId']!,
            semester: state.pathParameters['semester']!,
          ),
        ),
        GoRoute(
          path: Routes.unitDetail,
          builder: (context, state) => UnitDetailScreen(curriculumId: state.pathParameters['curriculumId']!),
        ),
        GoRoute(path: Routes.semesterCalendar, builder: (context, state) => const SemesterCalendarScreen()),
        GoRoute(path: Routes.notifications, builder: (context, state) => const NotificationsScreen()),
        GoRoute(path: Routes.documents, builder: (context, state) => const DocumentsScreen()),
        GoRoute(
          path: Routes.documentViewer,
          builder: (context, state) => DocumentViewerScreen(documentId: state.pathParameters['documentId']!),
        ),
        GoRoute(path: Routes.search, builder: (context, state) => const SearchScreen()),
        GoRoute(path: Routes.resources, builder: (context, state) => const ResourcesScreen()),
        GoRoute(path: Routes.favorites, builder: (context, state) => const FavoritesScreen()),
        GoRoute(path: Routes.settings, builder: (context, state) => const SettingsScreen()),
        GoRoute(path: Routes.about, builder: (context, state) => const AboutScreen()),
        GoRoute(path: Routes.assistant, builder: (context, state) => const AssistantScreen()),
      ],
    ),
    // Auth screens sit outside the ShellRoute so they render without the
    // bottom navigation bar — pushed on top of whichever tab the user was
    // on (e.g. from Settings), not part of the tabbed flow itself.
    GoRoute(path: Routes.login, builder: (context, state) => const LoginScreen()),
    GoRoute(path: Routes.signUp, builder: (context, state) => const SignUpScreen()),
    GoRoute(path: Routes.forgotPassword, builder: (context, state) => const ForgotPasswordScreen()),
  ],
);

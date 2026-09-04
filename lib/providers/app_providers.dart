import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../models/academic_calendar_model.dart';
import '../models/grade_model.dart';
import '../models/notification_model.dart';
import '../core/utils/semester_calculator.dart';
import '../repositories/academic_calendar_repository.dart';
import '../repositories/curriculum_repository.dart';
import '../repositories/documents_repository.dart';
import '../repositories/notifications_repository.dart';
import '../repositories/search_repository.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import '../services/curriculum_admin_service.dart';
import '../services/favorites_service.dart';
import '../services/fcm_service.dart';

// --- Firebase singletons -----------------------------------------------

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final functionsProvider = Provider<FirebaseFunctions>((ref) => FirebaseFunctions.instance);
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

// --- Auth ------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(firebaseAuthProvider)));

final authStateChangesProvider =
    StreamProvider<User?>((ref) => ref.watch(authServiceProvider).authStateChanges());

/// True only if the signed-in user's email is on the TEMPORARY admin
/// whitelist (AppConstants.adminEmails) — drives visibility of admin-only
/// UI (e.g. the curriculum seeding button in Settings). This does NOT use
/// Firebase custom claims (no service-account/Admin SDK/CLI setup needed).
/// It is still not the real security boundary: firestore.rules's
/// isAdminOrWhitelistedForCurriculum() independently checks request.auth.token.email
/// server-side, which a client can't spoof — this provider only controls
/// what's shown, matching the same pattern the custom-claim check used.
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authStateChangesProvider).value;
  final email = user?.email?.toLowerCase();
  return email != null && AppConstants.adminEmails.contains(email);
});

final curriculumAdminServiceProvider =
    Provider<CurriculumAdminService>((ref) => CurriculumAdminService(ref.watch(firestoreProvider)));

// --- Services (initialized in main() before runApp, overridden here) ---

final cacheServiceProvider = Provider<CacheService>((ref) {
  throw UnimplementedError('cacheServiceProvider must be overridden in main()');
});

final favoritesServiceProvider = Provider<FavoritesService>((ref) {
  throw UnimplementedError('favoritesServiceProvider must be overridden in main()');
});

final fcmServiceProvider = Provider<FcmService>((ref) => FcmService());

final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

final isOnlineProvider = StreamProvider<bool>((ref) => ref.watch(connectivityServiceProvider).onStatusChange);

// --- Repositories ---------------------------------------------------------

final curriculumRepositoryProvider =
    Provider((ref) => CurriculumRepository(ref.watch(firestoreProvider)));

final notificationsRepositoryProvider =
    Provider((ref) => NotificationsRepository(ref.watch(firestoreProvider)));

final documentsRepositoryProvider =
    Provider((ref) => DocumentsRepository(ref.watch(firestoreProvider)));

final academicCalendarRepositoryProvider =
    Provider((ref) => AcademicCalendarRepository(ref.watch(firestoreProvider)));

final searchRepositoryProvider = Provider((ref) => SearchRepository(ref.watch(firestoreProvider)));

// --- Derived data ---------------------------------------------------------

final gradesProvider = StreamProvider<List<GradeModel>>(
  (ref) => ref.watch(curriculumRepositoryProvider).watchGrades(),
);

final notificationsFeedProvider = StreamProvider.family<List<NotificationModel>, NotificationCategory?>(
  (ref, category) => ref.watch(notificationsRepositoryProvider).watchFeed(category: category),
);

final academicCalendarProvider = StreamProvider<List<AcademicCalendarModel>>(
  (ref) => ref.watch(academicCalendarRepositoryProvider).watchAll(),
);

final selectedZoneProvider = StateProvider<SemesterZone>((ref) => SemesterZone.summer);

final currentSemesterProvider = Provider<AcademicCalendarModel?>((ref) {
  final calendar = ref.watch(academicCalendarProvider).value ?? const [];
  final zone = ref.watch(selectedZoneProvider);
  return SemesterCalculator.currentSemester(calendar: calendar, zone: zone, now: DateTime.now());
});

final lastSyncedAtProvider = Provider<DateTime?>((ref) => ref.watch(cacheServiceProvider).lastSyncedAt);

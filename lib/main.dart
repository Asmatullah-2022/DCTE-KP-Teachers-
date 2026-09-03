import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'config/firebase_options.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/app_providers.dart';
import 'routing/app_router.dart';
import 'services/cache_service.dart';
import 'services/favorites_service.dart';

void main() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };

  // runZonedGuarded so an uncaught error anywhere in the async init chain
  // below (or later, off the widget tree) is logged instead of silently
  // preventing runApp() from ever being reached — that gap is exactly what
  // produced a blank screen on real devices when Firebase.initializeApp()
  // threw against the placeholder config in firebase_options.dart.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    var firebaseReady = false;
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      firebaseReady = true;
    } catch (error, stackTrace) {
      // lib/config/firebase_options.dart still ships placeholder values
      // until `flutterfire configure` is run (see README §6) — this is
      // expected to fail until then. Fall back to a visible screen instead
      // of leaving the app stuck on a blank one.
      debugPrint('Firebase.initializeApp() failed, running in fallback mode: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (firebaseReady) {
      // App Check is an anti-abuse layer, not a requirement for Firestore/
      // Auth/Storage to function — it must never be allowed to block the
      // rest of the app the way it previously did by sharing a try/catch
      // with Firebase.initializeApp() above. Play Integrity attestation
      // (the Android provider) requires the app to be recognized as
      // installed through Google Play; a sideloaded APK (installed
      // directly from a downloaded file, as during development/testing)
      // reliably fails this, which is expected and NOT a sign that
      // Firebase itself is misconfigured. Firestore/Auth/Storage still
      // work via the API key in firebase_options.dart regardless — App
      // Check just won't be enforced for this session.
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'FirebaseAppCheck.activate() failed — App Check will not be '
          'enforced this session, but Firebase itself is fine: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    final cacheService = CacheService();
    final favoritesService = FavoritesService();
    try {
      await Hive.initFlutter();
      await cacheService.init();
      await favoritesService.init();
    } catch (error, stackTrace) {
      debugPrint('Local storage initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    runApp(
      ProviderScope(
        overrides: [
          cacheServiceProvider.overrideWithValue(cacheService),
          favoritesServiceProvider.overrideWithValue(favoritesService),
        ],
        child: DcteKpTeachersApp(firebaseReady: firebaseReady),
      ),
    );
  }, (error, stackTrace) {
    debugPrint('Uncaught zone error: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

class DcteKpTeachersApp extends ConsumerStatefulWidget {
  final bool firebaseReady;

  const DcteKpTeachersApp({super.key, required this.firebaseReady});

  @override
  ConsumerState<DcteKpTeachersApp> createState() => _DcteKpTeachersAppState();
}

class _DcteKpTeachersAppState extends ConsumerState<DcteKpTeachersApp> {
  @override
  void initState() {
    super.initState();
    if (!widget.firebaseReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fcm = ref.read(fcmServiceProvider);
      try {
        await fcm.requestPermission();
        await fcm.applyStoredSubscriptions();
      } catch (error, stackTrace) {
        debugPrint('FCM setup failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.firebaseReady) {
      return const _FirebaseUnavailableApp();
    }
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Shown instead of a blank screen when Firebase couldn't initialize —
/// typically because lib/config/firebase_options.dart still has the
/// placeholder values it ships with until `flutterfire configure` is run
/// (see README §6). Confirms the app itself renders correctly even when
/// Firebase isn't reachable, rather than leaving the user looking at
/// nothing with no indication of what went wrong.
class _FirebaseUnavailableApp extends StatelessWidget {
  const _FirebaseUnavailableApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school, size: 48, color: Color(0xFF0B6E4F)),
                  const SizedBox(height: 16),
                  const Text(
                    'DCTE KP Teachers App',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'App is working successfully',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Firebase isn't configured yet, so this app is running "
                    'in fallback mode. Run `flutterfire configure` and '
                    'replace lib/config/firebase_options.dart with real '
                    'values to load curriculum, notifications, and '
                    'documents.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

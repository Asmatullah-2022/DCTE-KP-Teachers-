import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check protects Firestore/Storage/Functions from abuse. Play Integrity
  // is the production provider for Android; the debug provider is used for
  // local development (its token is printed to logcat on first run — add it
  // to the Firebase Console > App Check > Debug tokens for your dev device).
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

  await Hive.initFlutter();
  final cacheService = CacheService();
  await cacheService.init();
  final favoritesService = FavoritesService();
  await favoritesService.init();

  runApp(
    ProviderScope(
      overrides: [
        cacheServiceProvider.overrideWithValue(cacheService),
        favoritesServiceProvider.overrideWithValue(favoritesService),
      ],
      child: const DcteKpTeachersApp(),
    ),
  );
}

class DcteKpTeachersApp extends ConsumerStatefulWidget {
  const DcteKpTeachersApp({super.key});

  @override
  ConsumerState<DcteKpTeachersApp> createState() => _DcteKpTeachersAppState();
}

class _DcteKpTeachersAppState extends ConsumerState<DcteKpTeachersApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fcm = ref.read(fcmServiceProvider);
      await fcm.requestPermission();
      await fcm.applyStoredSubscriptions();
    });
  }

  @override
  Widget build(BuildContext context) {
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

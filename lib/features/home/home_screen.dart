import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../routing/app_router.dart';
import '../../widgets/home_feature_card.dart';
import '../../widgets/offline_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastSynced = ref.watch(lastSyncedAtProvider);
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final latestNotifications = ref.watch(notificationsFeedProvider(null));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF0B6E4F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(AppConstants.appName),
          ],
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {},
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(AppConstants.appSubtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
                  const SizedBox(height: 8),
                  _SyncStatusRow(online: online, lastSynced: lastSynced),
                  const SizedBox(height: 16),
                  HomeFeatureCard(
                    icon: Icons.menu_book,
                    title: 'Curriculum',
                    subtitle: 'ECE to Grade VIII, by subject and semester',
                    onTap: () => context.go(Routes.curriculum),
                  ),
                  HomeFeatureCard(
                    icon: Icons.campaign_outlined,
                    title: 'Latest Notifications',
                    subtitle: latestNotifications.maybeWhen(
                      data: (list) => list.isNotEmpty ? list.first.title : 'No notifications yet',
                      orElse: () => 'Loading…',
                    ),
                    onTap: () => context.go(Routes.notifications),
                  ),
                  HomeFeatureCard(
                    icon: Icons.calendar_month_outlined,
                    title: 'Semester Calendar',
                    subtitle: 'Summer & Winter zone academic dates',
                    onTap: () => context.go(Routes.semesterCalendar),
                  ),
                  HomeFeatureCard(
                    icon: Icons.folder_open_outlined,
                    title: 'Documents',
                    subtitle: 'Official notifications & scheme of studies',
                    onTap: () => context.go(Routes.documents),
                  ),
                  HomeFeatureCard(
                    icon: Icons.auto_stories_outlined,
                    title: 'Teacher Resources',
                    subtitle: 'Lesson plans, guides & training materials',
                    onTap: () => context.go(Routes.resources),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  final bool online;
  final DateTime? lastSynced;
  const _SyncStatusRow({required this.online, required this.lastSynced});

  @override
  Widget build(BuildContext context) {
    final text = lastSynced != null
        ? 'Last synchronized: ${DateFormat('MMM d, y • h:mm a').format(lastSynced!)}'
        : 'Not yet synchronized';
    return Row(
      children: [
        Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off, size: 16, color: online ? Colors.green.shade700 : Colors.orange.shade800),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12.5, color: Colors.black54))),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  NotificationCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(notificationsFeedProvider(_filter));

    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                ),
                for (final c in NotificationCategory.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(c.label),
                      selected: _filter == c,
                      onSelected: (_) => setState(() => _filter = c),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: feedAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorStateView.sourceUnavailable(),
              data: (items) {
                if (items.isEmpty) {
                  return const ErrorStateView(message: 'No notifications in this category yet.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final n = items[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Chip(label: Text(n.category.label), visualDensity: VisualDensity.compact),
                                if (n.isNew) ...[
                                  const SizedBox(width: 6),
                                  const Chip(
                                    label: Text('NEW'),
                                    backgroundColor: Colors.redAccent,
                                    labelStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                                const Spacer(),
                                if (n.isVerified) const Icon(Icons.verified, size: 16, color: Colors.green),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(n.title, style: Theme.of(context).textTheme.titleMedium),
                            if (n.publishedDate != null)
                              Text(DateFormat('MMM d, y').format(n.publishedDate!), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                            if (n.summary != null) ...[
                              const SizedBox(height: 6),
                              Text(n.summary!),
                            ],
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => launchUrl(Uri.parse(n.sourceUrl), mode: LaunchMode.externalApplication),
                              child: const Text('View Official Source', style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

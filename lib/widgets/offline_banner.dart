import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';

/// Shown wherever cached/offline data may be displayed, per the spec:
/// "If offline: show cached data and a clear offline indicator."
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    if (online) return const SizedBox.shrink();

    final lastSynced = ref.watch(lastSyncedAtProvider);
    final syncedText = lastSynced != null
        ? 'Last synchronized: ${DateFormat('MMM d, y • h:mm a').format(lastSynced)}'
        : 'No cached data synchronized yet';

    return Container(
      width: double.infinity,
      color: Colors.amber.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'You are offline. Showing cached data. $syncedText',
              style: const TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

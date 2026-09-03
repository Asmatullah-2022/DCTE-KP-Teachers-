import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../routing/app_router.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fcm = ref.watch(fcmServiceProvider);
    final authState = ref.watch(authStateChangesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          const _SectionHeader('Account'),
          authState.when(
            data: (user) => user == null
                ? ListTile(
                    leading: const Icon(Icons.login),
                    title: const Text('Sign In'),
                    subtitle: const Text('Sync favorites and preferences'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.login),
                  )
                : ListTile(
                    leading: const Icon(Icons.account_circle_outlined),
                    title: Text(user.email ?? 'Signed in'),
                    subtitle: const Text('Tap to log out'),
                    trailing: const Icon(Icons.logout),
                    onTap: () => ref.read(authServiceProvider).signOut(),
                  ),
            loading: () => const ListTile(
              leading: Icon(Icons.account_circle_outlined),
              title: Text('Loading…'),
            ),
            error: (error, stackTrace) => ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Sign In'),
              subtitle: const Text('Account status unavailable'),
              onTap: () => context.push(Routes.login),
            ),
          ),
          const Divider(),
          const _SectionHeader('Notification Categories'),
          for (final topic in AppConstants.fcmTopics)
            FutureBuilder<bool>(
              future: fcm.isTopicEnabled(topic),
              builder: (context, snapshot) {
                final enabled = snapshot.data ?? true;
                return SwitchListTile(
                  title: Text(_topicLabel(topic)),
                  value: enabled,
                  onChanged: (v) async {
                    await fcm.setTopicEnabled(topic, v);
                    (context as Element).markNeedsBuild();
                  },
                );
              },
            ),
          const Divider(),
          const _SectionHeader('More'),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('Favorites'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/favorites'),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Teacher Resources'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/resources'),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('DCTE Assistant (beta)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/assistant'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About & Disclaimer'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go('/settings/about'),
          ),
        ],
      ),
    );
  }

  String _topicLabel(String topic) {
    switch (topic) {
      case 'dcte_all':
        return 'All Updates';
      case 'dcte_curriculum':
        return 'Curriculum';
      case 'dcte_notifications':
        return 'Notifications';
      case 'dcte_assessment':
        return 'Assessment';
      case 'dcte_teacher_training':
        return 'Teacher Training';
      case 'dcte_academic':
        return 'Academic Calendar';
      default:
        return topic;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black54)),
    );
  }
}

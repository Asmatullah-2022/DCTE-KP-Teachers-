import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../models/curriculum_model.dart';
import '../../providers/app_providers.dart';
import '../../routing/app_router.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _seeding = false;
  bool _verifyingAll = false;
  final Set<String> _verifyingIds = {};

  Future<void> _seedGrade1English() async {
    setState(() => _seeding = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(curriculumAdminServiceProvider).seedBundledUnits(
            gradeId: 'grade-1',
            subjectId: 'english',
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.imported > 0
                ? '${result.imported} Grade 1 English units imported successfully.'
                : 'Grade 1 English units already imported (${result.alreadyPresent} present, nothing new to add).',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _verifyAndPublish(String curriculumId) async {
    setState(() => _verifyingIds.add(curriculumId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(curriculumAdminServiceProvider).verifyAndPublish(curriculumId);
      messenger.showSnackBar(const SnackBar(content: Text('Curriculum verified and published successfully.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Verification failed: $e')));
    } finally {
      if (mounted) setState(() => _verifyingIds.remove(curriculumId));
    }
  }

  Future<void> _verifyAllGrade1EnglishSemesterI() async {
    setState(() => _verifyingAll = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(curriculumAdminServiceProvider).verifyAllPending(
            gradeId: 'grade-1',
            subjectId: 'english',
            semester: 'Semester I',
          );
      messenger.showSnackBar(const SnackBar(content: Text('Curriculum verified and published successfully.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Verification failed: $e')));
    } finally {
      if (mounted) setState(() => _verifyingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fcm = ref.watch(fcmServiceProvider);
    final authState = ref.watch(authStateChangesProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final pendingUnitsAsync = isAdmin ? ref.watch(pendingCurriculumUnitsProvider) : const AsyncValue<List<CurriculumModel>>.data([]);

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
          if (isAdmin) ...[
            const Divider(),
            const _SectionHeader('Admin Tools'),
            ListTile(
              leading: _seeding
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              title: const Text('Seed Grade 1 English Curriculum'),
              subtitle: const Text('Imports the 11 bundled units into live Firestore (skips any already there)'),
              enabled: !_seeding,
              onTap: _seedGrade1English,
            ),
            ListTile(
              leading: _verifyingAll
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add_check_outlined),
              title: const Text('Verify All & Publish — Grade 1 English, Semester I'),
              subtitle: const Text('Marks every pending unit in this grade/subject/semester as verified'),
              enabled: !_verifyingAll,
              onTap: _verifyAllGrade1EnglishSemesterI,
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Pending Curriculum Units', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            pendingUnitsAsync.when(
              data: (units) => units.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text('No units pending verification.', style: TextStyle(color: Colors.black54)),
                    )
                  : Column(
                      children: [
                        for (final unit in units)
                          ListTile(
                            dense: true,
                            title: Text(unit.unitTitle),
                            subtitle: Text('${unit.gradeId} • ${unit.subjectId} • ${unit.semester} • Unit ${unit.unitNumber}'),
                            trailing: _verifyingIds.contains(unit.curriculumId)
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(
                                    onPressed: () => _verifyAndPublish(unit.curriculumId),
                                    child: const Text('Verify & Publish'),
                                  ),
                          ),
                      ],
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Could not load pending units: $e', style: const TextStyle(color: Colors.red)),
              ),
            ),
          ],
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

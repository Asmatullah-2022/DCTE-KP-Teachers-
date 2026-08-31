import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/offline_banner.dart';

class CurriculumScreen extends ConsumerWidget {
  const CurriculumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gradesAsync = ref.watch(gradesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Curriculum')),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: gradesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, st) => ErrorStateView.sourceUnavailable(),
              data: (grades) {
                if (grades.isEmpty) {
                  return const ErrorStateView(message: 'No curriculum data available yet.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: grades.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final grade = grades[i];
                    return Card(
                      child: ListTile(
                        title: Text(grade.displayName),
                        leading: const Icon(Icons.school_outlined),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.go('/curriculum/${grade.gradeId}'),
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

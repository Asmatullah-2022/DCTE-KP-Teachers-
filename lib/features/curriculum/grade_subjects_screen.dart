import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

class GradeSubjectsScreen extends ConsumerWidget {
  final String gradeId;
  const GradeSubjectsScreen({super.key, required this.gradeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(curriculumRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Subjects — $gradeId')),
      body: StreamBuilder(
        stream: repo.watchSubjectsForGrade(gradeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return ErrorStateView.sourceUnavailable();
          final subjects = snapshot.data ?? const [];
          if (subjects.isEmpty) {
            return const ErrorStateView(message: 'No subjects found for this grade yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final subject = subjects[i];
              return Card(
                child: ListTile(
                  title: Text(subject.name),
                  subtitle: subject.nameUrdu != null
                      ? Text(subject.nameUrdu!, textDirection: TextDirection.rtl)
                      : null,
                  leading: const Icon(Icons.book_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/curriculum/$gradeId/${subject.subjectId}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

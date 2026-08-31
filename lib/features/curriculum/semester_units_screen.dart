import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

class SemesterUnitsScreen extends ConsumerWidget {
  final String gradeId;
  final String subjectId;
  final String semester; // URL-encoded label, e.g. "Semester I"

  const SemesterUnitsScreen({
    super.key,
    required this.gradeId,
    required this.subjectId,
    required this.semester,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(curriculumRepositoryProvider);
    final semesterLabel = Uri.decodeComponent(semester);

    return Scaffold(
      appBar: AppBar(title: Text(semesterLabel)),
      body: StreamBuilder(
        stream: repo.watchUnits(gradeId: gradeId, subjectId: subjectId, semester: semesterLabel),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return ErrorStateView.sourceUnavailable();
          final units = snapshot.data ?? const [];
          if (units.isEmpty) {
            return const ErrorStateView(message: 'No units published for this semester yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: units.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final unit = units[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${unit.unitNumber}')),
                  title: Text(unit.unitTitle),
                  subtitle: unit.needsVerification
                      ? const Text('Needs verification', style: TextStyle(color: Colors.orange))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/curriculum/unit/${unit.curriculumId}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

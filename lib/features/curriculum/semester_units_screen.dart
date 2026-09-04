import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/curriculum_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

class SemesterUnitsScreen extends ConsumerStatefulWidget {
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
  ConsumerState<SemesterUnitsScreen> createState() => _SemesterUnitsScreenState();
}

class _SemesterUnitsScreenState extends ConsumerState<SemesterUnitsScreen> {
  // Created ONCE in initState, not on every build — calling
  // repo.watchUnits(...) directly inside build() would hand StreamBuilder a
  // brand-new Stream (and therefore a brand-new Firestore listener) on
  // every rebuild, however that rebuild was triggered.
  late final Stream<List<CurriculumModel>> _unitsStream;
  late final String _semesterLabel;

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    final repo = ref.read(curriculumRepositoryProvider);
    _unitsStream = repo.watchUnits(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_semesterLabel)),
      body: StreamBuilder<List<CurriculumModel>>(
        stream: _unitsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorStateView.sourceUnavailable();
          }
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

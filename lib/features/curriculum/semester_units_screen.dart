import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/curriculum_model.dart';
import '../../providers/app_providers.dart';
import '../../repositories/curriculum_repository.dart';
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
  late final String _semesterLabel;
  late CurriculumRepository _repo;

  // Created once (initState), recreated only on an explicit Retry — never
  // inline in build() — so this screen keeps exactly ONE Firestore listener
  // alive at a time. StreamBuilder cancels the previous subscription itself
  // when the `stream` instance it's given changes identity (its own
  // documented didUpdateWidget behavior), so Retry never leaves two
  // listeners running.
  late Stream<List<CurriculumModel>> _unitsStream;

  int? _lastLoggedCount;

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    _repo = ref.read(curriculumRepositoryProvider);
    _unitsStream = _repo.watchUnits(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel);
  }

  void _retry() {
    setState(() {
      _lastLoggedCount = null;
      _unitsStream = _repo.watchUnits(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel);
    });
  }

  void _logUiState(List<CurriculumModel> units) {
    final previous = _lastLoggedCount;
    final now = DateTime.now().toIso8601String().substring(11, 23);
    if (previous != null && previous > 0 && units.length == 0) {
      developer.log(
        '[UI][$now] WARNING: units changed $previous -> 0 for '
        'gradeId=${widget.gradeId} subjectId=${widget.subjectId} semester=$_semesterLabel '
        '(source: StreamBuilder in SemesterUnitsScreen._SemesterUnitsScreenState.build)',
        name: 'firestore',
      );
    }
    developer.log(
      '[UI][$now] rendering ${units.length} unit(s) gradeId=${widget.gradeId} '
      'subjectId=${widget.subjectId} semester=$_semesterLabel',
      name: 'firestore',
    );
    _lastLoggedCount = units.length;
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
            return ErrorStateView.sourceUnavailable(onRetry: _retry);
          }
          final units = snapshot.data ?? const [];
          WidgetsBinding.instance.addPostFrameCallback((_) => _logUiState(units));

          if (units.isEmpty) {
            return ErrorStateView(
              message: 'No units published for this semester yet.',
              onRetry: _retry,
            );
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

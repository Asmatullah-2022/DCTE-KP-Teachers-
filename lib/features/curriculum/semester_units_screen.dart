import 'dart:async';

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
  // inline in build() — so this screen keeps one stable Firestore listener
  // instead of resubscribing on every unrelated widget rebuild.
  late Stream<List<CurriculumModel>> _unitsStream;

  // A brand-new Firestore listener's FIRST emission can legitimately be an
  // empty local-cache snapshot, with the server's real (non-empty) answer
  // arriving a moment later on the same listener. Rather than showing the
  // user an actionable "empty" state for that transient first result, wait
  // a short grace period for a possible follow-up emission before treating
  // it as final.
  static const _emptyResultGracePeriod = Duration(seconds: 3);
  Timer? _emptyGraceTimer;
  bool _emptyConfirmed = false;

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    _repo = ref.read(curriculumRepositoryProvider);
    _resubscribe();
  }

  void _resubscribe() {
    _emptyGraceTimer?.cancel();
    _emptyConfirmed = false;
    _unitsStream = _repo.watchUnits(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel);
  }

  void _retry() {
    setState(_resubscribe);
  }

  void _onEmptyResult() {
    if (_emptyConfirmed || _emptyGraceTimer != null) return;
    _emptyGraceTimer = Timer(_emptyResultGracePeriod, () {
      if (!mounted) return;
      setState(() => _emptyConfirmed = true);
    });
  }

  @override
  void dispose() {
    _emptyGraceTimer?.cancel();
    super.dispose();
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
          if (units.isEmpty) {
            if (!_emptyConfirmed) {
              WidgetsBinding.instance.addPostFrameCallback((_) => _onEmptyResult());
              return const Center(child: CircularProgressIndicator());
            }
            return ErrorStateView(
              message: 'No units published for this semester yet.',
              onRetry: _retry,
            );
          }
          // Real data arrived — a pending grace-period check is now moot.
          _emptyGraceTimer?.cancel();
          _emptyGraceTimer = null;
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

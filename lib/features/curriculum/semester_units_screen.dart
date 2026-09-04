import 'dart:developer' as developer;

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
  // Created ONCE in initState, not on every build — the previous version
  // called repo.watchUnits(...) directly inside build(), which handed
  // StreamBuilder a brand-new Stream object (and therefore a brand-new
  // Firestore listener) on every rebuild, however that rebuild was
  // triggered. Holding a single stable stream instance for the lifetime of
  // this screen eliminates that as a source of spurious re-subscriptions.
  late final Stream<List<CurriculumModel>> _unitsStream;
  late final String _semesterLabel;

  // TEMPORARY in-app diagnostics (no adb needed) — every emission this
  // screen's StreamBuilder actually receives, with a timestamp and count,
  // so a later emission silently replacing an earlier successful one is
  // visible directly on-device. Remove this whole block once diagnosed.
  final List<String> _debugLog = [];
  int _buildCount = 0;
  String? _lastLoggedSignature;

  /// [signature] identifies THIS emission's content (e.g. doc count + doc
  /// ids) — StreamBuilder re-invokes its builder on any rebuild of this
  /// widget (not just new stream events), including the rebuild THIS
  /// method's own setState triggers, so without deduplication this would
  /// feed back into itself forever.
  void _debugAppend(String signature, String line) {
    if (signature == _lastLoggedSignature) return;
    _lastLoggedSignature = signature;
    final entry = '${TimeOfDay.now().format(context)} — $line';
    developer.log('CURRICULUM DEBUG (UI): $entry', name: 'firestore');
    if (!mounted) return;
    setState(() {
      _debugLog.insert(0, entry);
      if (_debugLog.length > 12) _debugLog.removeLast();
    });
  }

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    final repo = ref.read(curriculumRepositoryProvider);
    _unitsStream = repo.watchUnits(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel);
    developer.log(
      'CURRICULUM DEBUG (UI): SemesterUnitsScreen.initState — ONE stream created for '
      'gradeId="${widget.gradeId}" subjectId="${widget.subjectId}" semester="$_semesterLabel"',
      name: 'firestore',
    );
  }

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    developer.log('CURRICULUM DEBUG (UI): SemesterUnitsScreen.build() call #$_buildCount', name: 'firestore');

    return Scaffold(
      appBar: AppBar(title: Text(_semesterLabel)),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.amber.shade50,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DEBUG — build() calls: $_buildCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ..._debugLog.map((line) => Text(line, style: const TextStyle(fontSize: 11))),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<CurriculumModel>>(
              stream: _unitsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _debugAppend('error:${snapshot.error}', 'STREAM ERROR: ${snapshot.error}'),
                  );
                  return ErrorStateView.sourceUnavailable();
                }
                final units = snapshot.data ?? const [];
                final signature = 'data:${units.map((u) => u.curriculumId).join(",")}';
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _debugAppend(
                    signature,
                    'StreamBuilder emission: ${units.length} unit(s) — ${units.map((u) => u.unitTitle).join(", ")}',
                  ),
                );
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
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
  // Created ONCE in initState, not on every build — see the commit that
  // fixed the previous version calling repo.watchUnits(...) directly
  // inside build(), which handed StreamBuilder a brand-new Stream (and
  // therefore a brand-new Firestore listener) on every rebuild.
  late final Stream<CurriculumDebugSnapshot> _debugStream;
  late final String _semesterLabel;
  late final Future<CurriculumRawDebugResult> _rawDebugFuture;

  // TEMPORARY on-screen diagnostics (no adb/Android Studio needed) — every
  // field requested: current vs previous count, timestamp, cache/pending
  // flags, data source, emission number, build() count, and whether a
  // 5-to-0-style drop just happened. Remove this whole file's debug panel
  // (and CurriculumRepository.watchUnitsWithDebugInfo) once diagnosed.
  int _buildCount = 0;
  int? _previousCount; // tracker: the count as of the last-processed emission
  int? _displayPreviousCount; // frozen "previous" value for the panel to show
  CurriculumDebugSnapshot? _lastSnapshot;
  bool _justDroppedToEmpty = false;
  final List<String> _history = [];
  int? _lastRecordedEmissionNumber;

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    final repo = ref.read(curriculumRepositoryProvider);
    _debugStream = repo.watchUnitsWithDebugInfo(
      gradeId: widget.gradeId,
      subjectId: widget.subjectId,
      semester: _semesterLabel,
    );
    _rawDebugFuture = repo.debugFetchFilteredVsUnfiltered(
      gradeId: widget.gradeId,
      subjectId: widget.subjectId,
      semester: _semesterLabel,
    );
  }

  void _recordEmission(CurriculumDebugSnapshot snap) {
    // StreamBuilder re-invokes its builder on ANY rebuild of this widget
    // (not just new stream events), including the rebuild THIS method's
    // own setState triggers — dedupe by emission number (only incremented
    // on genuinely new stream events) or this feeds back into itself.
    if (snap.emissionNumber == _lastRecordedEmissionNumber) return;
    _lastRecordedEmissionNumber = snap.emissionNumber;

    final currentCount = snap.units.length;
    final previousCount = _previousCount;
    final droppedToEmpty = previousCount != null && previousCount > 0 && currentCount == 0;

    final line = '#${snap.emissionNumber} @ ${_formatTime(snap.timestamp)} — '
        '${previousCount ?? "-"} → $currentCount unit(s) | '
        'source=${snap.source == CurriculumDataSource.firestore ? "Firestore" : "local fallback"} | '
        'isFromCache=${snap.isFromCache} | hasPendingWrites=${snap.hasPendingWrites}'
        '${droppedToEmpty ? "  ⚠ DROPPED TO EMPTY" : ""}';

    if (!mounted) return;
    setState(() {
      _lastSnapshot = snap;
      _displayPreviousCount = previousCount;
      _previousCount = currentCount;
      _justDroppedToEmpty = droppedToEmpty;
      _history.insert(0, line);
      if (_history.length > 15) _history.removeLast();
    });
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  @override
  Widget build(BuildContext context) {
    _buildCount++;

    return Scaffold(
      appBar: AppBar(title: Text(_semesterLabel)),
      body: Column(
        children: [
          _DebugPanel(
            buildCount: _buildCount,
            snapshot: _lastSnapshot,
            previousCount: _displayPreviousCount,
            justDroppedToEmpty: _justDroppedToEmpty,
            history: _history,
          ),
          FutureBuilder<CurriculumRawDebugResult>(
            future: _rawDebugFuture,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Loading raw collection dump…', style: TextStyle(fontSize: 11)),
                );
              }
              return _RawDumpPanel(result: snap.data!);
            },
          ),
          Expanded(
            child: StreamBuilder<CurriculumDebugSnapshot>(
              stream: _debugStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorStateView.sourceUnavailable();
                }
                final debugSnap = snapshot.data;
                if (debugSnap == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                WidgetsBinding.instance.addPostFrameCallback((_) => _recordEmission(debugSnap));

                final units = debugSnap.units;
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

class _DebugPanel extends StatelessWidget {
  final int buildCount;
  final CurriculumDebugSnapshot? snapshot;
  final int? previousCount;
  final bool justDroppedToEmpty;
  final List<String> history;

  const _DebugPanel({
    required this.buildCount,
    required this.snapshot,
    required this.previousCount,
    required this.justDroppedToEmpty,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final snap = snapshot;
    return Container(
      width: double.infinity,
      color: justDroppedToEmpty ? Colors.red.shade100 : Colors.amber.shade50,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('DEBUG PANEL (temporary)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text('build() calls: $buildCount', style: const TextStyle(fontSize: 11)),
            if (snap != null) ...[
              Text('Emission #: ${snap.emissionNumber}', style: const TextStyle(fontSize: 11)),
              Text('Current unit count: ${snap.units.length}', style: const TextStyle(fontSize: 11)),
              Text('Previous unit count: ${previousCount ?? "-"}', style: const TextStyle(fontSize: 11)),
              Text('Timestamp: ${snap.timestamp}', style: const TextStyle(fontSize: 11)),
              Text('Source: ${snap.source == CurriculumDataSource.firestore ? "Firestore" : "local fallback"}',
                  style: const TextStyle(fontSize: 11)),
              Text('isFromCache: ${snap.isFromCache}', style: const TextStyle(fontSize: 11)),
              Text('hasPendingWrites: ${snap.hasPendingWrites}', style: const TextStyle(fontSize: 11)),
              if (justDroppedToEmpty)
                const Text('⚠ LIST JUST DROPPED FROM >0 TO 0',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
            ] else
              const Text('Waiting for first emission…', style: TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            const Text('History (newest first):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            for (final line in history) Text(line, style: const TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// TEMPORARY — one-shot filtered-vs-unfiltered comparison and raw document
/// dump (see CurriculumRepository.debugFetchFilteredVsUnfiltered). Remove
/// alongside the rest of this file's debug panels once diagnosed.
class _RawDumpPanel extends StatelessWidget {
  final CurriculumRawDebugResult result;
  const _RawDumpPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    const maxDocsShown = 20;
    final shown = result.docs.take(maxDocsShown).toList();

    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 320),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('RAW COLLECTION DUMP (temporary)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text('FILTERED QUERY RESULT:', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text('count = ${result.filteredCount}', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            Text('UNFILTERED COLLECTION RESULT:', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            Text('count = ${result.unfilteredCount}', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            Text(
              'Showing ${shown.length} of ${result.docs.length} document(s):',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            for (final doc in shown) _RawDocView(doc: doc),
            if (result.docs.isEmpty)
              const Text('(the curriculum collection is completely empty)',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }
}

class _RawDocView extends StatelessWidget {
  final CurriculumRawDoc doc;
  const _RawDocView({required this.doc});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('id: ${doc.id}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text('gradeId: ${doc.gradeId} (${doc.gradeIdType})', style: const TextStyle(fontSize: 10)),
          Text('subjectId: ${doc.subjectId} (${doc.subjectIdType})', style: const TextStyle(fontSize: 10)),
          Text('semester: ${doc.semester} (${doc.semesterType})', style: const TextStyle(fontSize: 10)),
          Text('needsVerification: ${doc.needsVerification} (${doc.needsVerificationType})', style: const TextStyle(fontSize: 10)),
          Text('unitNumber: ${doc.unitNumber} (${doc.unitNumberType})', style: const TextStyle(fontSize: 10)),
          Text('status/published field: ${doc.statusOrPublishedField ?? "(none found)"}', style: const TextStyle(fontSize: 10)),
          Text('all fields: ${doc.data}', style: const TextStyle(fontSize: 9, color: Colors.black54)),
        ],
      ),
    );
  }
}

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

  // Created once (initState), recreated only on an explicit Retry — this is
  // the SAME stream instance the production StreamBuilder below renders.
  // The debug panel observes it via watchUnits()'s onDebugEvent callback —
  // it does not run a second query.
  late Stream<List<CurriculumModel>> _unitsStream;
  String _currentListenerId = '(not yet subscribed)';

  // TEMPORARY on-screen live debug panel — every event from the REAL
  // production watchUnits() stream, plus every distinct UI AsyncSnapshot
  // state this screen's own StreamBuilder receives. Remove this whole
  // panel (and CurriculumStreamEvent / onDebugEvent in the repository)
  // once diagnosed.
  final List<_DebugLogLine> _log = [];
  int? _lastKnownCount;
  String? _lastUiSignature;

  @override
  void initState() {
    super.initState();
    _semesterLabel = Uri.decodeComponent(widget.semester);
    _repo = ref.read(curriculumRepositoryProvider);
    _subscribe();
  }

  void _subscribe() {
    _unitsStream = _repo.watchUnits(
      gradeId: widget.gradeId,
      subjectId: widget.subjectId,
      semester: _semesterLabel,
      onDebugEvent: _onStreamDebugEvent,
    );
  }

  void _retry() {
    setState(() {
      _lastUiSignature = null;
      _lastKnownCount = null; // a fresh listener's first result is not a "drop"
      _subscribe();
    });
  }

  void _addLog(_DebugLogLine line) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, line);
      if (_log.length > 20) _log.removeLast();
    });
  }

  // Called SYNCHRONOUSLY from inside the repository's stream pipeline
  // (from the SAME watchUnits() call the StreamBuilder below is
  // subscribed to) — every FIRESTORE and REPOSITORY event this screen's
  // real data actually goes through.
  void _onStreamDebugEvent(CurriculumStreamEvent event) {
    _currentListenerId = event.listenerId;
    if (event.stage == 'subscribe') {
      _addLog(_DebugLogLine.subscribe(event));
      return;
    }
    if (event.stage == 'firestore') {
      final previous = _lastKnownCount;
      final dropped = previous != null && previous > 0 && event.docCount == 0;
      _lastKnownCount = event.docCount;
      _addLog(_DebugLogLine.firestore(event, droppedFromNonZero: dropped));
      return;
    }
    if (event.stage == 'repository') {
      _addLog(_DebugLogLine.repository(event));
    }
  }

  // Called from the StreamBuilder's builder — logs the UI-visible
  // AsyncSnapshot state whenever it actually changes (deduped so
  // StreamBuilder re-invoking builder() on unrelated rebuilds doesn't
  // spam the log or feed back into its own setState).
  void _logUiSnapshot(AsyncSnapshot<List<CurriculumModel>> snapshot) {
    final signature = '${snapshot.connectionState}|${snapshot.hasData}|${snapshot.hasError}|${snapshot.data?.length}';
    if (signature == _lastUiSignature) return;
    _lastUiSignature = signature;
    _addLog(_DebugLogLine.ui(snapshot, listenerId: _currentListenerId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_semesterLabel)),
      body: Column(
        children: [
          _LiveDebugPanel(gradeId: widget.gradeId, subjectId: widget.subjectId, semester: _semesterLabel, log: _log),
          Expanded(
            child: StreamBuilder<List<CurriculumModel>>(
              stream: _unitsStream,
              builder: (context, snapshot) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _logUiSnapshot(snapshot));

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorStateView.sourceUnavailable(onRetry: _retry);
                }
                final units = snapshot.data ?? const [];
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
          ),
        ],
      ),
    );
  }
}

/// TEMPORARY — one formatted log entry for the live debug panel. Built from
/// either a [CurriculumStreamEvent] (repository/Firestore stages) or a
/// StreamBuilder [AsyncSnapshot] (UI stage).
class _DebugLogLine {
  final String stage;
  final DateTime timestamp;
  final String text;
  final bool isWarning;

  const _DebugLogLine({required this.stage, required this.timestamp, required this.text, this.isWarning = false});

  factory _DebugLogLine.subscribe(CurriculumStreamEvent e) => _DebugLogLine(
        stage: 'SUBSCRIBE',
        timestamp: e.timestamp,
        text: 'Listener ${e.listenerId} created\n'
            'gradeId=${e.gradeId} subjectId=${e.subjectId} semester=${e.semester}',
      );

  factory _DebugLogLine.firestore(CurriculumStreamEvent e, {required bool droppedFromNonZero}) => _DebugLogLine(
        stage: 'FIRESTORE',
        timestamp: e.timestamp,
        isWarning: droppedFromNonZero,
        text: '[${e.listenerId}] docs=${e.docCount} ids=[${e.docIds?.join(", ")}]\n'
            'isFromCache=${e.isFromCache} hasPendingWrites=${e.hasPendingWrites}'
            '${droppedFromNonZero ? '\nWARNING: COUNT DROPPED FROM ${e.docCount == 0 ? ">0" : e.docCount} TO 0' : ''}',
      );

  factory _DebugLogLine.repository(CurriculumStreamEvent e) => _DebugLogLine(
        stage: 'REPOSITORY',
        timestamp: e.timestamp,
        text: '[${e.listenerId}] output count=${e.repositoryCount}',
      );

  factory _DebugLogLine.ui(AsyncSnapshot<List<CurriculumModel>> s, {required String listenerId}) => _DebugLogLine(
        stage: 'UI',
        timestamp: DateTime.now(),
        text: '[$listenerId] connectionState=${s.connectionState.name} hasData=${s.hasData} '
            'hasError=${s.hasError}${s.hasError ? ' error=${s.error}' : ''} '
            'data.length=${s.data?.length ?? "null"}',
      );
}

class _LiveDebugPanel extends StatelessWidget {
  final String gradeId;
  final String subjectId;
  final String semester;
  final List<_DebugLogLine> log;

  const _LiveDebugPanel({required this.gradeId, required this.subjectId, required this.semester, required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black87,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(maxHeight: 340),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('══════ LIVE STREAM DEBUG ══════',
                style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Text('Selected parameters — gradeId=$gradeId subjectId=$subjectId semester=$semester',
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            const SizedBox(height: 6),
            const Text('STREAM EVENTS (newest first, last 20):',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
            for (int i = 0; i < log.length; i++) _LogEntryView(index: log.length - i, line: log[i]),
            if (log.isEmpty)
              const Text('(waiting for first event…)', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _LogEntryView extends StatelessWidget {
  final int index;
  final _DebugLogLine line;
  const _LogEntryView({required this.index, required this.line});

  @override
  Widget build(BuildContext context) {
    final color = line.isWarning ? Colors.redAccent : Colors.greenAccent.shade100;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Event #$index — ${line.stage} @ ${line.timestamp.toIso8601String().substring(11, 23)}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
          ),
          Text(line.text, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/source_attribution.dart';

class SemesterCalendarScreen extends ConsumerWidget {
  const SemesterCalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(selectedZoneProvider);
    final calendarAsync = ref.watch(academicCalendarProvider);
    final current = ref.watch(currentSemesterProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Semester Calendar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<SemesterZone>(
              segments: const [
                ButtonSegment(value: SemesterZone.summer, label: Text('Summer Zone')),
                ButtonSegment(value: SemesterZone.winter, label: Text('Winter Zone')),
              ],
              selected: {zone},
              onSelectionChanged: (s) => ref.read(selectedZoneProvider.notifier).state = s.first,
            ),
          ),
          if (current != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                color: Colors.green.shade50,
                child: ListTile(
                  leading: const Icon(Icons.event_available, color: Colors.green),
                  title: Text('Current: ${current.semester.label}'),
                  subtitle: Text(
                    '${DateFormat('MMM d').format(current.startDate)} – ${DateFormat('MMM d, y').format(current.endDate)}',
                  ),
                ),
              ),
            ),
          Expanded(
            child: calendarAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => ErrorStateView.sourceUnavailable(),
              data: (all) {
                final entries = all.where((c) => c.zone == zone).toList()
                  ..sort((a, b) => a.startDate.compareTo(b.startDate));
                if (entries.isEmpty) {
                  return const ErrorStateView(message: 'Academic calendar not published yet.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.semester.label, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              '${DateFormat('MMM d, y').format(e.startDate)} – ${DateFormat('MMM d, y').format(e.endDate)}',
                            ),
                            if (e.label.isNotEmpty) Text(e.label, style: const TextStyle(color: Colors.black54)),
                            if (e.examWeightagePercent != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Examination weightage: ${e.examWeightagePercent}%',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                            if (e.policyNote != null) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(e.policyNote!, style: const TextStyle(fontSize: 12.5)),
                              ),
                            ],
                            const SizedBox(height: 8),
                            SourceAttribution(
                              department: 'DCTE / KPESE',
                              sourceUrl: AppConstants.dcteSemesterNotificationPdf,
                              sourcePage: e.sourcePage,
                            ),
                          ],
                        ),
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

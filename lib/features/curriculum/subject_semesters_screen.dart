import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';

class SubjectSemestersScreen extends StatelessWidget {
  final String gradeId;
  final String subjectId;
  const SubjectSemestersScreen({super.key, required this.gradeId, required this.subjectId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Semester')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final semester in Semester.values)
            Card(
              child: ListTile(
                title: Text(semester.label),
                leading: const Icon(Icons.event_note_outlined),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(
                  '/curriculum/$gradeId/$subjectId/${Uri.encodeComponent(semester.label)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

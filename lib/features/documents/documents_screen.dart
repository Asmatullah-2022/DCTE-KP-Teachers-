import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: StreamBuilder(
        stream: repo.watchPublished(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return ErrorStateView.sourceUnavailable();
          final docs = snapshot.data ?? const [];
          if (docs.isEmpty) {
            return const ErrorStateView(message: 'No verified documents published yet.');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final d = docs[i];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(d.title),
                  subtitle: Text(
                    [
                      d.documentType,
                      if (d.publishedDate != null) DateFormat('MMM d, y').format(d.publishedDate!),
                    ].join(' • '),
                  ),
                  trailing: d.verified ? const Icon(Icons.verified, size: 18, color: Colors.green) : null,
                  onTap: () => context.go('/documents/${d.documentId}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

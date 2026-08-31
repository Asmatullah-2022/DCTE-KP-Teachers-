import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';

/// Teacher Resources reuses the `documents` collection filtered by
/// documentType, since resources are simply verified official documents
/// tagged into one of these categories. Only content imported from
/// verified official sources is ever shown — nothing is invented here.
const resourceCategories = [
  'Scripted Lesson Plans',
  'Assessment',
  'Teacher Training',
  'Teaching Materials',
  'Curriculum',
  'Teacher Guides',
];

class ResourcesScreen extends StatelessWidget {
  const ResourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teacher Resources')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: resourceCategories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final category = resourceCategories[i];
          return Card(
            child: ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: Text(category),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ResourceCategoryScreen(category: category)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ResourceCategoryScreen extends ConsumerWidget {
  final String category;
  const ResourceCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(category)),
      body: StreamBuilder(
        stream: repo.watchPublished(documentType: category),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data ?? const [];
          if (docs.isEmpty) {
            return const ErrorStateView(message: 'No verified resources in this category yet.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) => Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(docs[i].title),
                onTap: () => context.go('/documents/${docs[i].documentId}'),
              ),
            ),
          );
        },
      ),
    );
  }
}

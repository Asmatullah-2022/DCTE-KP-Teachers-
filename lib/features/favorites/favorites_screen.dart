import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import '../../services/favorites_service.dart';
import '../../widgets/error_state_view.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesServiceProvider);
    final unitIds = favorites.idsFor(FavoriteType.unit);
    final documentIds = favorites.idsFor(FavoriteType.document);
    final notificationIds = favorites.idsFor(FavoriteType.notification);

    final isEmpty = unitIds.isEmpty && documentIds.isEmpty && notificationIds.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: isEmpty
          ? const ErrorStateView(message: 'No favorites yet. Tap the heart icon on a unit, document, or notification to save it here.')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (unitIds.isNotEmpty) ...[
                  Text('Curriculum Units', style: Theme.of(context).textTheme.titleMedium),
                  for (final id in unitIds)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(id),
                        onTap: () => context.go('/curriculum/unit/$id'),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (documentIds.isNotEmpty) ...[
                  Text('Documents', style: Theme.of(context).textTheme.titleMedium),
                  for (final id in documentIds)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.picture_as_pdf_outlined),
                        title: Text(id),
                        onTap: () => context.go('/documents/$id'),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (notificationIds.isNotEmpty) ...[
                  Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
                  for (final id in notificationIds)
                    Card(child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(id))),
                ],
              ],
            ),
    );
  }
}

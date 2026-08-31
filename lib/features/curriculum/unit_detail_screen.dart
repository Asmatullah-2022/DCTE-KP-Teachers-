import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/curriculum_model.dart';
import '../../providers/app_providers.dart';
import '../../services/favorites_service.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/source_attribution.dart';

class UnitDetailScreen extends ConsumerWidget {
  final String curriculumId;
  const UnitDetailScreen({super.key, required this.curriculumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(curriculumRepositoryProvider);
    final favorites = ref.watch(favoritesServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit'),
        actions: [
          IconButton(
            icon: Icon(
              favorites.isFavorite(FavoriteType.unit, curriculumId) ? Icons.favorite : Icons.favorite_border,
            ),
            onPressed: () async {
              await favorites.toggle(FavoriteType.unit, curriculumId);
              (context as Element).markNeedsBuild();
            },
          ),
        ],
      ),
      body: FutureBuilder<CurriculumModel?>(
        future: repo.getUnit(curriculumId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final unit = snapshot.data;
          if (unit == null) return ErrorStateView.sourceUnavailable();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Unit ${unit.unitNumber}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
              const SizedBox(height: 4),
              Text(unit.unitTitle, style: Theme.of(context).textTheme.titleLarge),
              if (unit.unitTitleUrdu != null) ...[
                const SizedBox(height: 4),
                Text(unit.unitTitleUrdu!, textDirection: TextDirection.rtl, style: Theme.of(context).textTheme.titleMedium),
              ],
              const SizedBox(height: 12),
              if (unit.needsVerification)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: const Text(
                    'This item is pending admin verification. Please confirm details against the original source document.',
                    style: TextStyle(color: Colors.deepOrange, fontSize: 13),
                  ),
                ),
              if (unit.description != null) ...[
                Text(unit.description!, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 16),
              ],
              Text('Session: ${unit.session}', style: Theme.of(context).textTheme.bodyMedium),
              Text('Semester: ${unit.semester}', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              SourceAttribution(
                department: 'DCTE',
                sourceUrl: unit.sourceUrl,
                sourcePage: unit.sourcePage,
              ),
            ],
          );
        },
      ),
    );
  }
}

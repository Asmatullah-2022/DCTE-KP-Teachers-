import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

/// Global search across grades/subjects/units/notifications/documents.
///
/// Firestore has no native full-text search, so indexed documents must
/// carry a `searchKeywords: List<String>` field (lower-cased tokens of
/// title/name/summary) populated at write time (by the import script or
/// Cloud Functions). This repository does `array-contains` prefix-style
/// matching against that field. See firebase/firestore.indexes.json for
/// the composite indexes this requires.
class SearchResult {
  final String id;
  final String collection;
  final String title;
  final String subtitle;

  SearchResult({required this.id, required this.collection, required this.title, required this.subtitle});
}

class SearchRepository {
  final FirebaseFirestore _db;
  SearchRepository(this._db);

  Future<List<SearchResult>> search(String query, {int limitPerCollection = 15}) async {
    final token = query.trim().toLowerCase();
    if (token.isEmpty) return [];

    final collections = <String, String Function(Map<String, dynamic>)>{
      AppConstants.collectionGrades: (m) => m['displayName'] as String? ?? '',
      AppConstants.collectionSubjects: (m) => m['name'] as String? ?? '',
      AppConstants.collectionCurriculum: (m) => m['unitTitle'] as String? ?? '',
      AppConstants.collectionNotifications: (m) => m['title'] as String? ?? '',
      AppConstants.collectionDocuments: (m) => m['title'] as String? ?? '',
    };

    final results = <SearchResult>[];
    for (final entry in collections.entries) {
      final snap = await _db
          .collection(entry.key)
          .where('searchKeywords', arrayContains: token)
          .limit(limitPerCollection)
          .get();
      for (final doc in snap.docs) {
        results.add(SearchResult(
          id: doc.id,
          collection: entry.key,
          title: entry.value(doc.data()),
          subtitle: entry.key,
        ));
      }
    }
    return results;
  }
}

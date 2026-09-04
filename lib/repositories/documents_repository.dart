import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/firestore_error_logger.dart';
import '../models/document_model.dart';

class DocumentsRepository {
  final FirebaseFirestore _db;
  DocumentsRepository(this._db);

  /// firestore.rules only allows public reads where BOTH status=='published'
  /// AND verified==true (see firebase/firestore.rules) — a list query whose
  /// filters don't match that exactly is rejected outright with
  /// permission-denied, regardless of the actual data. The previous version
  /// of this query filtered on status only, so it could never succeed once
  /// rules were deployed. See firebase/firestore.indexes.json for the
  /// matching composite indexes this now requires.
  Stream<List<DocumentModel>> watchPublished({String? documentType}) async* {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.collectionDocuments)
        .where('status', isEqualTo: 'published')
        .where('verified', isEqualTo: true);
    if (documentType != null) {
      q = q.where('documentType', isEqualTo: documentType);
    }
    q = q.orderBy('publishedDate', descending: true);
    try {
      yield* q.snapshots().map((s) => s.docs.map(DocumentModel.fromDoc).toList());
    } catch (e, st) {
      logFirestoreError('DocumentsRepository.watchPublished', e, st);
      rethrow;
    }
  }

  Future<DocumentModel?> getById(String documentId) async {
    try {
      final doc = await _db.collection(AppConstants.collectionDocuments).doc(documentId).get();
      return doc.exists ? DocumentModel.fromDoc(doc) : null;
    } catch (e, st) {
      logFirestoreError('DocumentsRepository.getById', e, st);
      rethrow;
    }
  }
}

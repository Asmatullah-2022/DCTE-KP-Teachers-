import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/document_model.dart';

class DocumentsRepository {
  final FirebaseFirestore _db;
  DocumentsRepository(this._db);

  Stream<List<DocumentModel>> watchPublished({String? documentType}) {
    Query<Map<String, dynamic>> q = _db
        .collection(AppConstants.collectionDocuments)
        .where('status', isEqualTo: 'published');
    if (documentType != null) {
      q = q.where('documentType', isEqualTo: documentType);
    }
    q = q.orderBy('publishedDate', descending: true);
    return q.snapshots().map((s) => s.docs.map(DocumentModel.fromDoc).toList());
  }

  Future<DocumentModel?> getById(String documentId) async {
    final doc = await _db.collection(AppConstants.collectionDocuments).doc(documentId).get();
    return doc.exists ? DocumentModel.fromDoc(doc) : null;
  }
}

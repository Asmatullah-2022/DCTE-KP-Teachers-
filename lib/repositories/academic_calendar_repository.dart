import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/academic_calendar_model.dart';

class AcademicCalendarRepository {
  final FirebaseFirestore _db;
  AcademicCalendarRepository(this._db);

  Stream<List<AcademicCalendarModel>> watchAll() {
    return _db
        .collection(AppConstants.collectionAcademicCalendar)
        .orderBy('startDate')
        .snapshots()
        .map((s) => s.docs.map(AcademicCalendarModel.fromDoc).toList());
  }
}

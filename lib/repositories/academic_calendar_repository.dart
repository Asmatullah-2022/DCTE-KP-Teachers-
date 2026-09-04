import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/firestore_fallback.dart';
import '../models/academic_calendar_model.dart';
import 'local_academic_calendar_data.dart';

class AcademicCalendarRepository {
  final FirebaseFirestore _db;
  AcademicCalendarRepository(this._db);

  Stream<List<AcademicCalendarModel>> watchAll() async* {
    final local = await LocalAcademicCalendarData.calendar();
    final remote = _db
        .collection(AppConstants.collectionAcademicCalendar)
        .orderBy('startDate')
        .snapshots()
        .map((s) => s.docs.map(AcademicCalendarModel.fromDoc).toList());
    yield* withLocalFallback('AcademicCalendarRepository.watchAll', remote, local);
  }
}

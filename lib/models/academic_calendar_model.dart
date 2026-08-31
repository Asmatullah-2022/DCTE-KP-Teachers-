import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

/// One semester window for one zone/session. Dates live entirely in
/// Firestore (never hard-coded in UI) so they can be corrected via the
/// admin panel if the official notification changes.
class AcademicCalendarModel {
  final String calendarId;
  final String session; // e.g. "2025-26"
  final SemesterZone zone;
  final Semester semester;
  final DateTime startDate;
  final DateTime endDate;
  final String label;
  final String? sourceDocumentId;
  final int? sourcePage;
  final bool verified;
  final int? examWeightagePercent;
  final String? policyNote;

  const AcademicCalendarModel({
    required this.calendarId,
    required this.session,
    required this.zone,
    required this.semester,
    required this.startDate,
    required this.endDate,
    required this.label,
    this.sourceDocumentId,
    this.sourcePage,
    this.verified = false,
    this.examWeightagePercent,
    this.policyNote,
  });

  bool containsDate(DateTime date) =>
      !date.isBefore(startDate) && !date.isAfter(endDate);

  factory AcademicCalendarModel.fromMap(String id, Map<String, dynamic> map) {
    return AcademicCalendarModel(
      calendarId: id,
      session: map['session'] as String? ?? '',
      zone: (map['zone'] as String?) == 'winter' ? SemesterZone.winter : SemesterZone.summer,
      semester: (map['semester'] as String?) == 'Semester II' ? Semester.semesterII : Semester.semesterI,
      startDate: (map['startDate'] as Timestamp).toDate(),
      endDate: (map['endDate'] as Timestamp).toDate(),
      label: map['label'] as String? ?? '',
      sourceDocumentId: map['sourceDocumentId'] as String?,
      sourcePage: (map['sourcePage'] as num?)?.toInt(),
      verified: map['verified'] as bool? ?? false,
      examWeightagePercent: (map['examWeightagePercent'] as num?)?.toInt(),
      policyNote: map['policyNote'] as String?,
    );
  }

  factory AcademicCalendarModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AcademicCalendarModel.fromMap(doc.id, doc.data() ?? const {});
}

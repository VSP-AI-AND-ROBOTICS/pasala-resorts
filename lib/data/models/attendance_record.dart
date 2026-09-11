/// One staff/accountant member's daily attendance record. [staffName] is
/// populated only when the row came with an embedded `profiles` object
/// (the repository's `list()` always joins it) -- `null` is never treated
/// as an error, just "no name on this particular response."
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.staffId,
    required this.workDate,
    required this.checkInAt,
    this.staffName,
    this.checkOutAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime workDate;
  final DateTime checkInAt;
  final DateTime? checkOutAt;

  /// True while the staff member has checked in but not yet checked out
  /// for [workDate]. Pure so both screens can share the same "what state
  /// is this record in" rule without duplicating a null check.
  bool get isCheckedIn => checkOutAt == null;

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) => AttendanceRecord(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: (json['profiles'] as Map<String, dynamic>?)?['full_name']
            as String?,
        workDate: DateTime.parse(json['work_date'] as String),
        checkInAt: DateTime.parse(json['check_in_at'] as String),
        checkOutAt: json['check_out_at'] == null
            ? null
            : DateTime.parse(json['check_out_at'] as String),
      );
}

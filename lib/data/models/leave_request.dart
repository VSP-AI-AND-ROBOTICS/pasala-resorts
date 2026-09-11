enum LeaveStatus { pending, approved, rejected }

LeaveStatus leaveStatusFromDb(String raw) => switch (raw) {
      'pending' => LeaveStatus.pending,
      'approved' => LeaveStatus.approved,
      'rejected' => LeaveStatus.rejected,
      _ => throw ArgumentError('unknown leave status $raw'),
    };

String leaveStatusToDb(LeaveStatus status) => switch (status) {
      LeaveStatus.pending => 'pending',
      LeaveStatus.approved => 'approved',
      LeaveStatus.rejected => 'rejected',
    };

/// One staff/accountant member's leave request. [staffName] is populated
/// only when the row came with an embedded `profiles` object (the
/// repository's `list()` always joins it; a bare insert/update response
/// does not) -- `null` is never treated as an error, just "no name on
/// this particular response."
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.staffId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.staffName,
    this.reason,
    this.decidedBy,
    this.decidedAt,
    this.createdAt,
  });

  final String id;
  final String staffId;
  final String? staffName;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final LeaveStatus status;
  final String? decidedBy;
  final DateTime? decidedAt;
  final DateTime? createdAt;

  factory LeaveRequest.fromJson(Map<String, dynamic> json) => LeaveRequest(
        id: json['id'] as String,
        staffId: json['staff_id'] as String,
        staffName: (json['profiles'] as Map<String, dynamic>?)?['full_name']
            as String?,
        startDate: DateTime.parse(json['start_date'] as String),
        endDate: DateTime.parse(json['end_date'] as String),
        reason: json['reason'] as String?,
        status: leaveStatusFromDb(json['status'] as String),
        decidedBy: json['decided_by'] as String?,
        decidedAt: json['decided_at'] == null
            ? null
            : DateTime.parse(json['decided_at'] as String),
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );

  /// Payload for a new request -- deliberately excludes `id`
  /// (server-assigned), `status` (server defaults to `pending`;
  /// `leave_requests_own_insert`'s `with check` requires it stay that
  /// way on insert), `decided_by`/`decided_at` (set only by
  /// [LeaveRequestRepository.decide]), and `staff_name` (a read-only
  /// join result, not a column).
  Map<String, dynamic> toInsert() => {
        'staff_id': staffId,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
        'reason': reason,
      };
}

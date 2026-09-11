/// One row of `staff_performance_summary(staff_id, from, to)`. Every figure
/// is computed server-side, same discipline as [DashboardSummary] --
/// `null` averages (a staff member with nothing to average, e.g. no
/// completed tasks yet) are treated as zero rather than left null.
class StaffPerformance {
  const StaffPerformance({
    required this.staffId,
    required this.staffName,
    required this.tasksAssigned,
    required this.tasksCompleted,
    required this.completionRatePct,
    required this.avgCompletionHours,
    required this.daysPresent,
    required this.leaveDaysApproved,
    required this.avgCheckinDelayMinutes,
  });

  final String staffId;
  final String staffName;
  final int tasksAssigned;
  final int tasksCompleted;
  final num completionRatePct;
  final num avgCompletionHours;
  final int daysPresent;
  final int leaveDaysApproved;
  final num avgCheckinDelayMinutes;

  factory StaffPerformance.fromJson(Map<String, dynamic> json) =>
      StaffPerformance(
        staffId: json['staff_id'] as String,
        staffName: json['staff_name'] as String? ?? '',
        tasksAssigned: (json['tasks_assigned'] as num?)?.toInt() ?? 0,
        tasksCompleted: (json['tasks_completed'] as num?)?.toInt() ?? 0,
        completionRatePct: (json['completion_rate_pct'] as num?) ?? 0,
        avgCompletionHours: (json['avg_completion_hours'] as num?) ?? 0,
        daysPresent: (json['days_present'] as num?)?.toInt() ?? 0,
        leaveDaysApproved: (json['leave_days_approved'] as num?)?.toInt() ?? 0,
        avgCheckinDelayMinutes:
            (json['avg_checkin_delay_minutes'] as num?) ?? 0,
      );
}

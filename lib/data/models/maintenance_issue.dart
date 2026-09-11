enum MaintenanceCategory {
  ac,
  electrical,
  plumbing,
  water,
  furniture,
  appliance,
  internet,
  poolFacility,
}

MaintenanceCategory maintenanceCategoryFromDb(String raw) => switch (raw) {
      'ac' => MaintenanceCategory.ac,
      'electrical' => MaintenanceCategory.electrical,
      'plumbing' => MaintenanceCategory.plumbing,
      'water' => MaintenanceCategory.water,
      'furniture' => MaintenanceCategory.furniture,
      'appliance' => MaintenanceCategory.appliance,
      'internet' => MaintenanceCategory.internet,
      'pool_facility' => MaintenanceCategory.poolFacility,
      _ => throw ArgumentError('unknown maintenance category $raw'),
    };

String maintenanceCategoryToDb(MaintenanceCategory category) => switch (category) {
      MaintenanceCategory.ac => 'ac',
      MaintenanceCategory.electrical => 'electrical',
      MaintenanceCategory.plumbing => 'plumbing',
      MaintenanceCategory.water => 'water',
      MaintenanceCategory.furniture => 'furniture',
      MaintenanceCategory.appliance => 'appliance',
      MaintenanceCategory.internet => 'internet',
      MaintenanceCategory.poolFacility => 'pool_facility',
    };

String maintenanceCategoryLabel(MaintenanceCategory category) => switch (category) {
      MaintenanceCategory.ac => 'AC',
      MaintenanceCategory.electrical => 'Electrical',
      MaintenanceCategory.plumbing => 'Plumbing',
      MaintenanceCategory.water => 'Water',
      MaintenanceCategory.furniture => 'Furniture',
      MaintenanceCategory.appliance => 'Appliance',
      MaintenanceCategory.internet => 'Internet',
      MaintenanceCategory.poolFacility => 'Pool / Facility',
    };

enum MaintenancePriority { low, medium, high }

MaintenancePriority maintenancePriorityFromDb(String raw) => switch (raw) {
      'low' => MaintenancePriority.low,
      'medium' => MaintenancePriority.medium,
      'high' => MaintenancePriority.high,
      _ => throw ArgumentError('unknown maintenance priority $raw'),
    };

String maintenancePriorityToDb(MaintenancePriority priority) => switch (priority) {
      MaintenancePriority.low => 'low',
      MaintenancePriority.medium => 'medium',
      MaintenancePriority.high => 'high',
    };

String maintenancePriorityLabel(MaintenancePriority priority) => switch (priority) {
      MaintenancePriority.low => 'Low',
      MaintenancePriority.medium => 'Medium',
      MaintenancePriority.high => 'High',
    };

enum MaintenanceStatus { reported, assigned, inProgress, fixed, closed }

MaintenanceStatus maintenanceStatusFromDb(String raw) => switch (raw) {
      'reported' => MaintenanceStatus.reported,
      'assigned' => MaintenanceStatus.assigned,
      'in_progress' => MaintenanceStatus.inProgress,
      'fixed' => MaintenanceStatus.fixed,
      'closed' => MaintenanceStatus.closed,
      _ => throw ArgumentError('unknown maintenance status $raw'),
    };

String maintenanceStatusToDb(MaintenanceStatus status) => switch (status) {
      MaintenanceStatus.reported => 'reported',
      MaintenanceStatus.assigned => 'assigned',
      MaintenanceStatus.inProgress => 'in_progress',
      MaintenanceStatus.fixed => 'fixed',
      MaintenanceStatus.closed => 'closed',
    };

String maintenanceStatusLabel(MaintenanceStatus status) => switch (status) {
      MaintenanceStatus.reported => 'Reported',
      MaintenanceStatus.assigned => 'Assigned',
      MaintenanceStatus.inProgress => 'In Progress',
      MaintenanceStatus.fixed => 'Fixed',
      MaintenanceStatus.closed => 'Closed',
    };

class MaintenanceIssue {
  const MaintenanceIssue({
    required this.id,
    required this.reservationId,
    required this.category,
    required this.description,
    required this.priority,
    required this.status,
    this.photoUrl,
    this.assignedStaffId,
    this.assignedStaffName,
    this.createdAt,
  });

  final String id;
  final String reservationId;
  final MaintenanceCategory category;
  final String description;
  final String? photoUrl;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final DateTime? createdAt;

  factory MaintenanceIssue.fromJson(Map<String, dynamic> json) => MaintenanceIssue(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        category: maintenanceCategoryFromDb(json['category'] as String),
        description: json['description'] as String? ?? '',
        photoUrl: json['photo_url'] as String?,
        priority: maintenancePriorityFromDb(json['priority'] as String),
        status: maintenanceStatusFromDb(json['status'] as String),
        assignedStaffId: json['assigned_staff_id'] as String?,
        assignedStaffName:
            (json['assignee'] as Map<String, dynamic>?)?['full_name'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}

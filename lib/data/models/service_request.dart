enum ServiceRequestCategory { cleaning, water, extraBed, foodAssistance, generalAssistance }

ServiceRequestCategory serviceRequestCategoryFromDb(String raw) => switch (raw) {
      'cleaning' => ServiceRequestCategory.cleaning,
      'water' => ServiceRequestCategory.water,
      'extra_bed' => ServiceRequestCategory.extraBed,
      'food_assistance' => ServiceRequestCategory.foodAssistance,
      'general_assistance' => ServiceRequestCategory.generalAssistance,
      _ => throw ArgumentError('unknown service request category $raw'),
    };

String serviceRequestCategoryToDb(ServiceRequestCategory category) => switch (category) {
      ServiceRequestCategory.cleaning => 'cleaning',
      ServiceRequestCategory.water => 'water',
      ServiceRequestCategory.extraBed => 'extra_bed',
      ServiceRequestCategory.foodAssistance => 'food_assistance',
      ServiceRequestCategory.generalAssistance => 'general_assistance',
    };

String serviceRequestCategoryLabel(ServiceRequestCategory category) => switch (category) {
      ServiceRequestCategory.cleaning => 'Cleaning',
      ServiceRequestCategory.water => 'Water',
      ServiceRequestCategory.extraBed => 'Extra Bed',
      ServiceRequestCategory.foodAssistance => 'Food Assistance',
      ServiceRequestCategory.generalAssistance => 'General Assistance',
    };

enum ServiceRequestStatus { requested, assigned, inProgress, completed }

ServiceRequestStatus serviceRequestStatusFromDb(String raw) => switch (raw) {
      'requested' => ServiceRequestStatus.requested,
      'assigned' => ServiceRequestStatus.assigned,
      'in_progress' => ServiceRequestStatus.inProgress,
      'completed' => ServiceRequestStatus.completed,
      _ => throw ArgumentError('unknown service request status $raw'),
    };

String serviceRequestStatusToDb(ServiceRequestStatus status) => switch (status) {
      ServiceRequestStatus.requested => 'requested',
      ServiceRequestStatus.assigned => 'assigned',
      ServiceRequestStatus.inProgress => 'in_progress',
      ServiceRequestStatus.completed => 'completed',
    };

String serviceRequestStatusLabel(ServiceRequestStatus status) => switch (status) {
      ServiceRequestStatus.requested => 'Requested',
      ServiceRequestStatus.assigned => 'Assigned',
      ServiceRequestStatus.inProgress => 'In Progress',
      ServiceRequestStatus.completed => 'Completed',
    };

class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.reservationId,
    required this.category,
    required this.description,
    required this.status,
    this.assignedStaffId,
    this.assignedStaffName,
    this.createdAt,
  });

  final String id;
  final String reservationId;
  final ServiceRequestCategory category;
  final String description;
  final ServiceRequestStatus status;
  final String? assignedStaffId;
  final String? assignedStaffName;
  final DateTime? createdAt;

  factory ServiceRequest.fromJson(Map<String, dynamic> json) => ServiceRequest(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        category: serviceRequestCategoryFromDb(json['category'] as String),
        description: json['description'] as String? ?? '',
        status: serviceRequestStatusFromDb(json['status'] as String),
        assignedStaffId: json['assigned_staff_id'] as String?,
        assignedStaffName:
            (json['assignee'] as Map<String, dynamic>?)?['full_name'] as String?,
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}

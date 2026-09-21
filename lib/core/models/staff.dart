import 'package:flutter/foundation.dart';

@immutable
class StaffMember {
  final String id;
  final String resortId;
  final String inchargeId;
  final String name;
  final String roleTitle;
  final String phone;
  final String status; // 'active', 'on_leave', 'inactive'
  final DateTime joinDate;

  const StaffMember({
    required this.id,
    required this.resortId,
    required this.inchargeId,
    required this.name,
    required this.roleTitle,
    required this.phone,
    required this.status,
    required this.joinDate,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      inchargeId: json['incharge_id'] as String,
      name: json['name'] as String,
      roleTitle: json['role_title'] as String,
      phone: json['phone'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      joinDate: DateTime.parse(json['join_date'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'incharge_id': inchargeId,
      'name': name,
      'role_title': roleTitle,
      'phone': phone,
      'status': status,
      'join_date': joinDate.toIso8601String().split('T')[0],
    };
  }
}

@immutable
class StaffTask {
  final String id;
  final String resortId;
  final String inchargeId;
  final String? assignedToStaffId;
  final String title;
  final String description;
  final String priority; // 'low', 'medium', 'high'
  final String status; // 'pending', 'in_progress', 'completed'
  final String? timeToComplete;
  final DateTime? dueDate;
  final DateTime createdAt;

  const StaffTask({
    required this.id,
    required this.resortId,
    required this.inchargeId,
    this.assignedToStaffId,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    this.timeToComplete,
    this.dueDate,
    required this.createdAt,
  });

  factory StaffTask.fromJson(Map<String, dynamic> json) {
    return StaffTask(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      inchargeId: json['incharge_id'] as String,
      assignedToStaffId: json['assigned_to_staff_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      priority: json['priority'] as String? ?? 'medium',
      status: json['status'] as String? ?? 'pending',
      timeToComplete: json['time_to_complete'] as String?,
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date'] as String) : null,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'incharge_id': inchargeId,
      'assigned_to_staff_id': assignedToStaffId,
      'title': title,
      'description': description,
      'priority': priority,
      'status': status,
      'time_to_complete': timeToComplete,
      'due_date': dueDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  StaffTask copyWith({
    String? id,
    String? resortId,
    String? inchargeId,
    String? assignedToStaffId,
    String? title,
    String? description,
    String? priority,
    String? status,
    String? timeToComplete,
    DateTime? dueDate,
    DateTime? createdAt,
  }) {
    return StaffTask(
      id: id ?? this.id,
      resortId: resortId ?? this.resortId,
      inchargeId: inchargeId ?? this.inchargeId,
      assignedToStaffId: assignedToStaffId ?? this.assignedToStaffId,
      title: title ?? this.title,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      timeToComplete: timeToComplete ?? this.timeToComplete,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

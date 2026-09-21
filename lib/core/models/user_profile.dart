import 'package:flutter/foundation.dart';

enum AppRole {
  superAdmin,
  admin,
  incharge,
  accountant,
  customer;

  String get dbValue {
    switch (this) {
      case AppRole.superAdmin:
        return 'super_admin';
      case AppRole.admin:
        return 'admin';
      case AppRole.incharge:
        return 'incharge';
      case AppRole.accountant:
        return 'accountant';
      case AppRole.customer:
        return 'customer';
    }
  }

  static AppRole fromString(String roleStr) {
    switch (roleStr.toLowerCase()) {
      case 'super_admin':
      case 'superadmin':
      case 'co-owner':
      case 'co_owner':
        return AppRole.superAdmin;
      case 'admin':
      case 'resort_manager':
        return AppRole.admin;
      case 'incharge':
        return AppRole.incharge;
      case 'accountant':
        return AppRole.accountant;
      case 'customer':
      default:
        return AppRole.customer;
    }
  }

  String get displayName {
    switch (this) {
      case AppRole.superAdmin:
        return 'Co-owner / Super Admin';
      case AppRole.admin:
        return 'Resort Manager / Admin';
      case AppRole.incharge:
        return 'Incharge';
      case AppRole.accountant:
        return 'Accountant';
      case AppRole.customer:
        return 'Customer';
    }
  }
}

@immutable
class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final AppRole role;
  final String? resortId;
  final String? phone;
  final String? avatarUrl;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.resortId,
    this.phone,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      fullName: json['full_name'] as String? ?? 'User',
      role: AppRole.fromString(json['role'] as String? ?? 'customer'),
      resortId: json['resort_id'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role.dbValue,
      'resort_id': resortId,
      'phone': phone,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? fullName,
    AppRole? role,
    String? resortId,
    String? phone,
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      resortId: resortId ?? this.resortId,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

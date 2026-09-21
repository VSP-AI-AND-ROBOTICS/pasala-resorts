import 'package:flutter/foundation.dart';

@immutable
class FoodItem {
  final String id;
  final String resortId;
  final String categoryName;
  final String name;
  final String description;
  final double price;
  final bool isAvailable;

  const FoodItem({
    required this.id,
    required this.resortId,
    required this.categoryName,
    required this.name,
    required this.description,
    required this.price,
    required this.isAvailable,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      categoryName: json['category_name'] as String? ?? 'General',
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      price: (json['price'] as num).toDouble(),
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'category_name': categoryName,
      'name': name,
      'description': description,
      'price': price,
      'is_available': isAvailable,
    };
  }
}

@immutable
class FoodOrder {
  final String id;
  final String resortId;
  final String roomNumber;
  final List<Map<String, dynamic>> items;
  final double totalAmount;
  final String status; // 'pending', 'preparing', 'delivered', 'cancelled'
  final DateTime createdAt;

  const FoodOrder({
    required this.id,
    required this.resortId,
    required this.roomNumber,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  factory FoodOrder.fromJson(Map<String, dynamic> json) {
    return FoodOrder(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      roomNumber: json['room_number'] as String,
      items: (json['items'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
      totalAmount: (json['total_amount'] as num).toDouble(),
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'room_number': roomNumber,
      'items': items,
      'total_amount': totalAmount,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

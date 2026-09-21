import 'package:flutter/foundation.dart';

@immutable
class ResortUnit {
  final String id;
  final String resortId;
  final String name;
  final String type; // 'villa', 'suite', 'deluxe', 'cottage'
  final int capacity;
  final double pricePerNight;
  final String description;
  final String status; // 'available', 'maintenance', 'occupied'
  final List<String> amenities;
  final List<String> imageUrls;

  const ResortUnit({
    required this.id,
    required this.resortId,
    required this.name,
    required this.type,
    required this.capacity,
    required this.pricePerNight,
    required this.description,
    required this.status,
    required this.amenities,
    required this.imageUrls,
  });

  factory ResortUnit.fromJson(Map<String, dynamic> json) {
    return ResortUnit(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String? ?? 'deluxe',
      capacity: json['capacity'] as int? ?? 2,
      pricePerNight: (json['price_per_night'] as num).toDouble(),
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'available',
      amenities: (json['amenities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'name': name,
      'type': type,
      'capacity': capacity,
      'price_per_night': pricePerNight,
      'description': description,
      'status': status,
      'amenities': amenities,
      'image_urls': imageUrls,
    };
  }

  ResortUnit copyWith({
    String? id,
    String? resortId,
    String? name,
    String? type,
    int? capacity,
    double? pricePerNight,
    String? description,
    String? status,
    List<String>? amenities,
    List<String>? imageUrls,
  }) {
    return ResortUnit(
      id: id ?? this.id,
      resortId: resortId ?? this.resortId,
      name: name ?? this.name,
      type: type ?? this.type,
      capacity: capacity ?? this.capacity,
      pricePerNight: pricePerNight ?? this.pricePerNight,
      description: description ?? this.description,
      status: status ?? this.status,
      amenities: amenities ?? this.amenities,
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }
}

@immutable
class RateRule {
  final String id;
  final String resortId;
  final String? unitId;
  final DateTime startDate;
  final DateTime endDate;
  final double? priceOverride;
  final double priceMultiplier;
  final String reason;

  const RateRule({
    required this.id,
    required this.resortId,
    this.unitId,
    required this.startDate,
    required this.endDate,
    this.priceOverride,
    this.priceMultiplier = 1.0,
    required this.reason,
  });

  factory RateRule.fromJson(Map<String, dynamic> json) {
    return RateRule(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      unitId: json['unit_id'] as String?,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      priceOverride: (json['price_override'] as num?)?.toDouble(),
      priceMultiplier: (json['price_multiplier'] as num?)?.toDouble() ?? 1.0,
      reason: json['reason'] as String? ?? 'special_pricing',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'unit_id': unitId,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'price_override': priceOverride,
      'price_multiplier': priceMultiplier,
      'reason': reason,
    };
  }
}

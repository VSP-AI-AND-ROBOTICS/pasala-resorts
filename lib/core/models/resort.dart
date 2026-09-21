import 'package:flutter/foundation.dart';

enum SubscriptionTier {
  premium,
  superTier,
  basic,
  free;

  String get dbValue {
    switch (this) {
      case SubscriptionTier.premium:
        return 'premium';
      case SubscriptionTier.superTier:
        return 'super';
      case SubscriptionTier.basic:
        return 'basic';
      case SubscriptionTier.free:
        return 'free';
    }
  }

  static SubscriptionTier fromString(String str) {
    switch (str.toLowerCase()) {
      case 'premium':
        return SubscriptionTier.premium;
      case 'super':
      case 'supertier':
        return SubscriptionTier.superTier;
      case 'basic':
        return SubscriptionTier.basic;
      case 'free':
      default:
        return SubscriptionTier.free;
    }
  }

  int get priorityOrder {
    switch (this) {
      case SubscriptionTier.premium:
        return 3;
      case SubscriptionTier.superTier:
        return 2;
      case SubscriptionTier.basic:
        return 1;
      case SubscriptionTier.free:
        return 0;
    }
  }

  String get badgeText {
    switch (this) {
      case SubscriptionTier.premium:
        return 'PREMIUM';
      case SubscriptionTier.superTier:
        return 'SUPER';
      case SubscriptionTier.basic:
        return 'BASIC';
      case SubscriptionTier.free:
        return 'FREE';
    }
  }
}

@immutable
class Resort {
  final String id;
  final String name;
  final String slug;
  final String description;
  final String address;
  final String city;
  final String state;
  final String country;
  final double latitude;
  final double longitude;
  final String contactEmail;
  final String contactPhone;
  final SubscriptionTier subscriptionTier;
  final String status; // 'active', 'inactive'
  final List<String> imageUrls;
  final List<String> amenities;
  final double? calculatedDistanceKm; // Dynamically computed for location sorting
  final double rating;

  const Resort({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.contactEmail,
    required this.contactPhone,
    required this.subscriptionTier,
    required this.status,
    required this.imageUrls,
    required this.amenities,
    this.calculatedDistanceKm,
    this.rating = 4.5,
  });

  factory Resort.fromJson(Map<String, dynamic> json) {
    return Resort(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      country: json['country'] as String? ?? 'India',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      contactEmail: json['contact_email'] as String? ?? '',
      contactPhone: json['contact_phone'] as String? ?? '',
      subscriptionTier: SubscriptionTier.fromString(json['subscription_tier'] as String? ?? 'free'),
      status: json['status'] as String? ?? 'active',
      imageUrls: (json['image_urls'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      amenities: (json['amenities'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      rating: (json['rating'] as num?)?.toDouble() ?? 4.5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'subscription_tier': subscriptionTier.dbValue,
      'status': status,
      'image_urls': imageUrls,
      'amenities': amenities,
      'rating': rating,
    };
  }

  Resort copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    String? address,
    String? city,
    String? state,
    String? country,
    double? latitude,
    double? longitude,
    String? contactEmail,
    String? contactPhone,
    SubscriptionTier? subscriptionTier,
    String? status,
    List<String>? imageUrls,
    List<String>? amenities,
    double? calculatedDistanceKm,
    double? rating,
  }) {
    return Resort(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      subscriptionTier: subscriptionTier ?? this.subscriptionTier,
      status: status ?? this.status,
      imageUrls: imageUrls ?? this.imageUrls,
      amenities: amenities ?? this.amenities,
      calculatedDistanceKm: calculatedDistanceKm ?? this.calculatedDistanceKm,
      rating: rating ?? this.rating,
    );
  }
}

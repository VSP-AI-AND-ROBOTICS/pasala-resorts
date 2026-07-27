class Property {
  const Property({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.address,
    required this.images,
    required this.amenities,
    required this.checkInTime,
    required this.checkOutTime,
    required this.isActive,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? address;
  final List<String> images;
  final List<String> amenities;
  final String checkInTime;
  final String checkOutTime;
  final bool isActive;

  factory Property.fromJson(Map<String, dynamic> json) => Property(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        description: json['description'] as String?,
        address: json['address'] as String?,
        images: (json['images'] as List<dynamic>? ?? []).cast<String>(),
        amenities: (json['amenities'] as List<dynamic>? ?? []).cast<String>(),
        checkInTime: json['check_in_time'] as String? ?? '14:00',
        checkOutTime: json['check_out_time'] as String? ?? '11:00',
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toInsert() => {
        'name': name,
        'slug': slug,
        'description': description,
        'address': address,
        'images': images,
        'amenities': amenities,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        'is_active': isActive,
      };
}

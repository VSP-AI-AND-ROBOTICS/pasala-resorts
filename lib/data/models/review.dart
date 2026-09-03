class Review {
  const Review({
    required this.id,
    required this.reservationId,
    required this.customerId,
    required this.farmhouseRating,
    required this.cleanlinessRating,
    required this.foodRating,
    required this.serviceRating,
    required this.activitiesRating,
    required this.overallRating,
    required this.feedback,
    this.createdAt,
    this.customerFirstName,
  });

  final String id;
  final String reservationId;
  final String customerId;
  final int farmhouseRating;
  final int cleanlinessRating;
  final int foodRating;
  final int serviceRating;
  final int activitiesRating;
  final int overallRating;
  final String feedback;
  final DateTime? createdAt;

  /// From the `profiles` row [ReviewRepository.all]'s join embeds -- null
  /// wherever that join isn't requested (e.g. [ReviewRepository.submit]'s
  /// own insert-and-return, which has no reason to know the caller's own
  /// name back). Just the first word of `full_name`, never the full name,
  /// since this is shown to other customers, not just staff.
  final String? customerFirstName;

  factory Review.fromJson(Map<String, dynamic> json) {
    final profile = json['profiles'] as Map<String, dynamic>?;
    final fullName = profile?['full_name'] as String?;
    return Review(
      id: json['id'] as String,
      reservationId: json['reservation_id'] as String,
      customerId: json['customer_id'] as String,
      farmhouseRating: json['farmhouse_rating'] as int,
      cleanlinessRating: json['cleanliness_rating'] as int,
      foodRating: json['food_rating'] as int,
      serviceRating: json['service_rating'] as int,
      activitiesRating: json['activities_rating'] as int,
      overallRating: json['overall_rating'] as int,
      feedback: json['feedback'] as String? ?? '',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
      customerFirstName:
          (fullName == null || fullName.trim().isEmpty)
              ? null
              : fullName.trim().split(' ').first,
    );
  }

  /// Payload for a new review -- excludes `id`/`created_at` (server-assigned).
  Map<String, dynamic> toInsert() => {
        'reservation_id': reservationId,
        'customer_id': customerId,
        'farmhouse_rating': farmhouseRating,
        'cleanliness_rating': cleanlinessRating,
        'food_rating': foodRating,
        'service_rating': serviceRating,
        'activities_rating': activitiesRating,
        'overall_rating': overallRating,
        'feedback': feedback,
      };
}

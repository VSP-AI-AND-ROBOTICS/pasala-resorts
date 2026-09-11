/// An bookable on-site activity (e.g. "Swimming", "Bonfire") -- 0 as
/// [pricePerPerson] means free, still shown in the catalog.
class Activity {
  const Activity({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.pricePerPerson,
    required this.capacityPerSlot,
    required this.isAvailable,
    this.description,
  });

  final String id;
  final String propertyId;
  final String name;
  final String? description;
  final double pricePerPerson;
  final int capacityPerSlot;
  final bool isAvailable;

  factory Activity.fromJson(Map<String, dynamic> json) => Activity(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        pricePerPerson: (json['price_per_person'] as num).toDouble(),
        capacityPerSlot: json['capacity_per_slot'] as int,
        isAvailable: json['is_available'] as bool? ?? true,
      );
}

enum ActivityBookingStatus { booked, cancelled }

ActivityBookingStatus activityBookingStatusFromDb(String raw) => switch (raw) {
      'booked' => ActivityBookingStatus.booked,
      'cancelled' => ActivityBookingStatus.cancelled,
      _ => throw ArgumentError('unknown activity booking status $raw'),
    };

/// One guest's reservation of an activity slot. [amount] is the server's
/// own price snapshot (`price_per_person * people` at booking time).
/// [activityName] is populated only when the row came with an embedded
/// `activities` object.
class ActivityBooking {
  const ActivityBooking({
    required this.id,
    required this.reservationId,
    required this.activityId,
    required this.bookingDate,
    required this.startTime,
    required this.people,
    required this.amount,
    required this.status,
    this.activityName,
  });

  final String id;
  final String reservationId;
  final String activityId;
  final String? activityName;
  final DateTime bookingDate;
  final String startTime;
  final int people;
  final double amount;
  final ActivityBookingStatus status;

  factory ActivityBooking.fromJson(Map<String, dynamic> json) => ActivityBooking(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        activityId: json['activity_id'] as String,
        activityName:
            (json['activities'] as Map<String, dynamic>?)?['name'] as String?,
        bookingDate: DateTime.parse(json['booking_date'] as String),
        startTime: (json['start_time'] as String).substring(0, 5),
        people: json['people'] as int,
        amount: (json['amount'] as num).toDouble(),
        status: activityBookingStatusFromDb(json['status'] as String),
      );
}

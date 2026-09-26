import 'reservation.dart';

/// What `verify_stay_pass` returns for a genuine pass: the booking (with
/// the guest's name and phone), the resort the pass was signed for, and
/// the unit's name. The booking can be in any status -- reception sees a
/// cancelled or already checked-in booking for what it is.
class VerifiedPass {
  const VerifiedPass({
    required this.reservation,
    required this.propertyId,
    required this.unitName,
  });

  final Reservation reservation;
  final String propertyId;
  final String? unitName;

  /// The JSON is a `reservations` row plus `profiles {full_name, phone}`
  /// and `unit_name` -- the shape [Reservation.fromJson] already reads.
  factory VerifiedPass.fromJson(Map<String, dynamic> json) => VerifiedPass(
    reservation: Reservation.fromJson(json),
    propertyId: json['property_id'] as String,
    unitName: json['unit_name'] as String?,
  );
}

/// True when [text] is a check-in pass (format `rh1.`), not a booking code
/// or a name typed into reception's search. Surrounding whitespace -- a
/// paste, or a keyboard-wedge scanner's newline -- is ignored.
bool looksLikeStayPass(String text) => text.trim().startsWith('rh1.');

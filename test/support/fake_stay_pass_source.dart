import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/verified_pass.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';

/// In-memory [StayPassSource]. [tokens] maps a reservation id to the pass
/// `issue` returns (default `'rh1.fake-<id>'`); [verified] is what
/// `verify` returns. Set an `...Error` to make that call throw, and read
/// the call logs to assert what a screen asked for.
class FakeStayPassSource implements StayPassSource {
  final Map<String, String> tokens = {};
  Object? issueError;
  VerifiedPass? verified;
  Object? verifyError;

  final List<String> issueCalls = [];
  final List<String> verifyCalls = [];

  @override
  Future<String> issue(String reservationId) async {
    issueCalls.add(reservationId);
    if (issueError != null) throw issueError!;
    return tokens[reservationId] ?? 'rh1.fake-$reservationId';
  }

  @override
  Future<VerifiedPass> verify(String token) async {
    verifyCalls.add(token);
    if (verifyError != null) throw verifyError!;
    final result = verified;
    if (result == null) {
      throw StateError('FakeStayPassSource.verified is not set');
    }
    return result;
  }
}

/// A verified pass with defaults for a confirmed two-guest booking at
/// resort `p1`; override only what a test is about.
VerifiedPass verifiedPass({
  String id = '3f2a1b9c-0000-0000-0000-000000000000',
  String propertyId = 'p1',
  String unitId = 'u1',
  String? unitName = 'Cottage 1',
  ReservationStatus status = ReservationStatus.confirmed,
  String? customerName = 'Ravi Kumar',
  String? customerPhone = '9000000001',
}) => VerifiedPass(
  reservation: Reservation(
    id: id,
    unitId: unitId,
    start: DateTime.utc(2026, 9, 26, 8, 30),
    end: DateTime.utc(2026, 9, 28, 5, 30),
    kind: ReservationKind.booking,
    status: status,
    customerName: customerName,
    customerPhone: customerPhone,
    guests: 2,
  ),
  propertyId: propertyId,
  unitName: unitName,
);

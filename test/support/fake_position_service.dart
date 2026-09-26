import 'package:pasala/core/location/geo_point.dart';
import 'package:pasala/core/location/position_service.dart';

/// A [PositionService] that answers from fields and counts its calls.
class FakePositionService implements PositionService {
  FakePositionService({this.approximate, this.precise});

  GeoPoint? approximate;
  GeoPoint? precise;
  int approximateCalls = 0;
  int preciseCalls = 0;

  @override
  Future<GeoPoint?> approximatePosition() async {
    approximateCalls++;
    return approximate;
  }

  @override
  Future<GeoPoint?> precisePosition() async {
    preciseCalls++;
    return precise;
  }
}

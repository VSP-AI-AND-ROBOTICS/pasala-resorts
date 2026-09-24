import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';

/// One row of `platform_resorts()` -- a resort summary for the platform
/// console. No guest data: owner emails, and booking counts/revenue for
/// the last 30 and 365 days only (see the tenancy design spec's
/// "Platform functions" section).
class ResortSummary {
  const ResortSummary({
    required this.propertyId,
    required this.name,
    required this.status,
    required this.ownerEmails,
    required this.createdAt,
    required this.bookings30d,
    required this.revenue30d,
    required this.bookings365d,
    required this.revenue365d,
  });

  final String propertyId;
  final String name;

  /// `active` or `suspended` -- `properties.status`.
  final String status;
  final List<String> ownerEmails;
  final DateTime createdAt;
  final int bookings30d;
  final num revenue30d;
  final int bookings365d;
  final num revenue365d;

  factory ResortSummary.fromJson(Map<String, dynamic> json) => ResortSummary(
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        status: json['status'] as String,
        ownerEmails:
            (json['owner_emails'] as List<dynamic>? ?? []).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        bookings30d: (json['bookings_30d'] as num?)?.toInt() ?? 0,
        revenue30d: (json['revenue_30d'] as num?) ?? 0,
        bookings365d: (json['bookings_365d'] as num?)?.toInt() ?? 0,
        revenue365d: (json['revenue_365d'] as num?) ?? 0,
      );
}

/// The slice of [PlatformRepository] `PlatformScreen` needs. Extracted as
/// its own interface, mirroring [IcalSource]/`OutboxSource`, so tests can
/// override it with a fake instead of a real [SupabaseClient].
abstract class PlatformSource {
  Future<List<ResortSummary>> resorts();
  Future<void> setStatus(String propertyId, String status);
  Future<String> createResort(String name, String ownerEmail);
}

/// Drives the platform-admin-only RPCs (`platform_resorts`,
/// `set_resort_status`, `create_resort` -- migration
/// 0045_resort_functions.sql). The platform admin gets no row access to
/// any resort-owned table (see the tenancy design spec), so every call
/// here goes through a `security definer` function, never a direct table
/// read/write.
class PlatformRepository implements PlatformSource {
  PlatformRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<List<ResortSummary>> resorts() => _guard(() async {
        final rows = await _db.rpc('platform_resorts') as List<dynamic>;
        return rows
            .map((e) => ResortSummary.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  @override
  Future<void> setStatus(String propertyId, String status) =>
      _guard(() async {
        await _db.rpc('set_resort_status', params: {
          'p_property': propertyId,
          'p_status': status,
        });
      });

  @override
  Future<String> createResort(String name, String ownerEmail) =>
      _guard(() async {
        final id = await _db.rpc('create_resort', params: {
          'p_name': name,
          'p_owner_email': ownerEmail,
        });
        return id as String;
      });
}

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => PlatformRepository(ref.watch(supabaseProvider)),
);

/// [PlatformSource] seam around [platformRepositoryProvider], mirroring
/// `icalSourceProvider`: [PlatformScreen] only ever calls this, so tests
/// can override just this provider with a fake.
final platformSourceProvider = Provider<PlatformSource>(
  (ref) => ref.watch(platformRepositoryProvider),
);

final platformResortsProvider = FutureProvider<List<ResortSummary>>(
  (ref) => ref.watch(platformSourceProvider).resorts(),
);

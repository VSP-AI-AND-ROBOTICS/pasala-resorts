import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/service_request.dart';

/// The (assignedStaffId, status) an admin or staff screen wants to see --
/// mirrors [TaskFilter]'s own shape, so `FutureProvider.family` can key on
/// it directly.
typedef ServiceRequestFilter = ({
  String propertyId,
  String? assignedStaffId,
  ServiceRequestStatus? status,
});

class ServiceRequestRepository {
  ServiceRequestRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<ServiceRequest> create({
    required String reservationId,
    required ServiceRequestCategory category,
    String description = '',
  }) =>
      _guard(() async {
        final row = await _db.rpc('create_service_request', params: {
          'p_reservation_id': reservationId,
          'p_category': serviceRequestCategoryToDb(category),
          'p_description': description,
        });
        return ServiceRequest.fromJson(row as Map<String, dynamic>);
      });

  Future<List<ServiceRequest>> myRequests(String reservationId) => _guard(() async {
        final rows = await _db
            .from('service_requests')
            .select('*, assignee:profiles!service_requests_assigned_staff_id_fkey(full_name)')
            .eq('reservation_id', reservationId)
            .order('created_at', ascending: false);
        return rows.map((e) => ServiceRequest.fromJson(e)).toList();
      });

  Future<List<ServiceRequest>> list({
    required String propertyId,
    String? assignedStaffId,
    ServiceRequestStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('service_requests')
            .select('*, assignee:profiles!service_requests_assigned_staff_id_fkey(full_name)')
            .eq('property_id', propertyId);
        if (assignedStaffId != null) {
          query = query.eq('assigned_staff_id', assignedStaffId);
        }
        if (status != null) query = query.eq('status', serviceRequestStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows.map((e) => ServiceRequest.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> assign({required String id, required String staffId}) => _guard(() async {
        await _db.from('service_requests').update({'assigned_staff_id': staffId}).eq('id', id);
      });

  Future<void> updateStatus({required String id, required ServiceRequestStatus status}) =>
      _guard(() async {
        await _db
            .from('service_requests')
            .update({'status': serviceRequestStatusToDb(status)}).eq('id', id);
      });
}

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>(
  (ref) => ServiceRequestRepository(ref.watch(supabaseProvider)),
);

final myServiceRequestsProvider = FutureProvider.family<List<ServiceRequest>, String>(
  (ref, reservationId) =>
      ref.watch(serviceRequestRepositoryProvider).myRequests(reservationId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final serviceRequestsProvider =
    FutureProvider.family<List<ServiceRequest>, ServiceRequestFilter>(
  (ref, filter) => ref.watch(serviceRequestRepositoryProvider).list(
        propertyId: filter.propertyId,
        assignedStaffId: filter.assignedStaffId,
        status: filter.status,
      ),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

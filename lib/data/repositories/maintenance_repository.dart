import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/maintenance_issue.dart';

typedef MaintenanceFilter = ({
  String propertyId,
  String? assignedStaffId,
  MaintenanceStatus? status,
});

class MaintenanceRepository {
  MaintenanceRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// Uploads under `{uid}/{filename}`, the path prefix the
  /// `maintenance_photos_owner_upload` storage policy requires. Returns the
  /// storage object path (not a public URL -- the bucket is private).
  Future<String> uploadPhoto({
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) =>
      _guard(() async {
        final uid = _db.auth.currentUser?.id;
        if (uid == null) throw const NotPermitted();
        final path = '$uid/${DateTime.now().microsecondsSinceEpoch}_$filename';
        await _db.storage.from('maintenance-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType),
            );
        return path;
      });

  Future<MaintenanceIssue> report({
    required String reservationId,
    required MaintenanceCategory category,
    String description = '',
    String? photoUrl,
    MaintenancePriority priority = MaintenancePriority.medium,
  }) =>
      _guard(() async {
        final row = await _db.rpc('report_maintenance_issue', params: {
          'p_reservation_id': reservationId,
          'p_category': maintenanceCategoryToDb(category),
          'p_description': description,
          'p_photo_url': photoUrl,
          'p_priority': maintenancePriorityToDb(priority),
        });
        return MaintenanceIssue.fromJson(row as Map<String, dynamic>);
      });

  Future<List<MaintenanceIssue>> myIssues(String reservationId) => _guard(() async {
        final rows = await _db
            .from('maintenance_issues')
            .select('*, assignee:profiles!maintenance_issues_assigned_staff_id_fkey(full_name)')
            .eq('reservation_id', reservationId)
            .order('created_at', ascending: false);
        return rows.map((e) => MaintenanceIssue.fromJson(e)).toList();
      });

  Future<List<MaintenanceIssue>> list({
    required String propertyId,
    String? assignedStaffId,
    MaintenanceStatus? status,
  }) =>
      _guard(() async {
        dynamic query = _db
            .from('maintenance_issues')
            .select('*, assignee:profiles!maintenance_issues_assigned_staff_id_fkey(full_name)')
            .eq('property_id', propertyId);
        if (assignedStaffId != null) {
          query = query.eq('assigned_staff_id', assignedStaffId);
        }
        if (status != null) query = query.eq('status', maintenanceStatusToDb(status));
        final rows = await query.order('created_at', ascending: false) as List;
        return rows.map((e) => MaintenanceIssue.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> assign({required String id, required String staffId}) => _guard(() async {
        await _db.from('maintenance_issues').update({'assigned_staff_id': staffId}).eq('id', id);
      });

  Future<void> updateStatus({required String id, required MaintenanceStatus status}) =>
      _guard(() async {
        await _db
            .from('maintenance_issues')
            .update({'status': maintenanceStatusToDb(status)}).eq('id', id);
      });
}

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(supabaseProvider)),
);

final myMaintenanceIssuesProvider = FutureProvider.family<List<MaintenanceIssue>, String>(
  (ref, reservationId) =>
      ref.watch(maintenanceRepositoryProvider).myIssues(reservationId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

final maintenanceIssuesProvider =
    FutureProvider.family<List<MaintenanceIssue>, MaintenanceFilter>(
  (ref, filter) => ref.watch(maintenanceRepositoryProvider).list(
        propertyId: filter.propertyId,
        assignedStaffId: filter.assignedStaffId,
        status: filter.status,
      ),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

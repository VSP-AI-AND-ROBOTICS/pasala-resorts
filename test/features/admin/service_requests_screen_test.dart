import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/models/service_request.dart';
import 'package:pasala/data/repositories/service_request_repository.dart';
import 'package:pasala/features/admin/service_requests_screen.dart';

import '../../support/resort_roster.dart';

/// In-memory stand-in for [ServiceRequestRepository], mirroring
/// `FakeTaskRepository` in `tasks_screen_test.dart`. Each row is tracked
/// against the resort it belongs to, and [list] filters by it the same way
/// a real `.eq('property_id', propertyId)` query would -- so a test can
/// seed rows for two different resorts and assert only the current one's
/// reach the screen (Review Focus #1).
class FakeServiceRequestRepository implements ServiceRequestRepository {
  final List<ServiceRequest> store = [];
  final Map<String, String> _propertyIdByRequestId = {};
  final List<String> listedPropertyIds = [];
  final List<String> assignedIds = [];

  void addToResort(String propertyId, ServiceRequest request) {
    store.add(request);
    _propertyIdByRequestId[request.id] = propertyId;
  }

  @override
  Future<ServiceRequest> create({
    required String reservationId,
    required ServiceRequestCategory category,
    String description = '',
  }) async =>
      throw UnimplementedError('admin never creates a service request');

  @override
  Future<List<ServiceRequest>> myRequests(String reservationId) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<List<ServiceRequest>> list({
    required String propertyId,
    String? assignedStaffId,
    ServiceRequestStatus? status,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((r) {
      if (_propertyIdByRequestId[r.id] != propertyId) return false;
      if (assignedStaffId != null && r.assignedStaffId != assignedStaffId) return false;
      if (status != null && r.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> assign({required String id, required String staffId}) async {
    assignedIds.add(id);
    final i = store.indexWhere((r) => r.id == id);
    final existing = store[i];
    store[i] = ServiceRequest(
      id: existing.id,
      reservationId: existing.reservationId,
      category: existing.category,
      description: existing.description,
      status: existing.status,
      assignedStaffId: staffId,
      assignedStaffName: existing.assignedStaffName,
      createdAt: existing.createdAt,
    );
  }

  @override
  Future<void> updateStatus({
    required String id,
    required ServiceRequestStatus status,
  }) async {
    final i = store.indexWhere((r) => r.id == id);
    final existing = store[i];
    store[i] = ServiceRequest(
      id: existing.id,
      reservationId: existing.reservationId,
      category: existing.category,
      description: existing.description,
      status: status,
      assignedStaffId: existing.assignedStaffId,
      assignedStaffName: existing.assignedStaffName,
      createdAt: existing.createdAt,
    );
  }
}

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Widget _appFor(FakeServiceRequestRepository repo) => ProviderScope(
      overrides: [
        serviceRequestRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: const MaterialApp(home: ServiceRequestsScreen()),
    );

void main() {
  testWidgets('shows an empty state when no requests match', (tester) async {
    await tester.pumpWidget(_appFor(FakeServiceRequestRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No requests match this filter'), findsOneWidget);
  });

  testWidgets('lists an existing request with its category and status', (
    tester,
  ) async {
    final repo = FakeServiceRequestRepository()
      ..addToResort('p1', const ServiceRequest(
        id: 'r1',
        reservationId: 'res-1',
        category: ServiceRequestCategory.cleaning,
        description: 'Extra towels please',
        status: ServiceRequestStatus.requested,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Cleaning'), findsOneWidget);
    expect(find.text('Extra towels please'), findsOneWidget);
    expect(find.text('Requested'), findsOneWidget);
  });

  // Review Focus #1: a person with memberships at two resorts must never
  // see resort B's rows while working in resort A.
  testWidgets(
      'ServiceRequestRepository.list: rows from another resort never reach '
      'the screen', (tester) async {
    final repo = FakeServiceRequestRepository()
      ..addToResort('p1', const ServiceRequest(
        id: 'r1',
        reservationId: 'res-1',
        category: ServiceRequestCategory.cleaning,
        description: 'Resort A request',
        status: ServiceRequestStatus.requested,
      ))
      ..addToResort('p2', const ServiceRequest(
        id: 'r2',
        reservationId: 'res-2',
        category: ServiceRequestCategory.water,
        description: 'Resort B request',
        status: ServiceRequestStatus.requested,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Resort A request'), findsOneWidget);
    expect(find.text('Resort B request'), findsNothing);
    expect(repo.listedPropertyIds, everyElement('p1'));
  });

  // Final review C1: "Assign to" lists `list_resort_members` for the current
  // resort only -- never another resort's staff.
  testWidgets("the assign-to picker lists only the current resort's members",
      (tester) async {
    final repo = FakeServiceRequestRepository()
      ..addToResort('p1', const ServiceRequest(
        id: 'r1',
        reservationId: 'res-1',
        category: ServiceRequestCategory.cleaning,
        description: 'Extra towels please',
        status: ServiceRequestStatus.requested,
      ));
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });
}

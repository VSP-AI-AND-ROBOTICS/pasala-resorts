import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/maintenance_issue.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/maintenance_repository.dart';
import 'package:pasala/features/admin/maintenance_issues_screen.dart';

import '../../support/resort_roster.dart';

/// In-memory stand-in for [MaintenanceRepository], mirroring
/// `FakeTaskRepository` in `tasks_screen_test.dart`. Each row is tracked
/// against the resort it belongs to, and [list] filters by it the same way
/// a real `.eq('property_id', propertyId)` query would -- so a test can
/// seed rows for two different resorts and assert only the current one's
/// reach the screen (Review Focus #1).
class FakeMaintenanceRepository implements MaintenanceRepository {
  final List<MaintenanceIssue> store = [];
  final Map<String, String> _propertyIdByIssueId = {};
  final List<String> listedPropertyIds = [];
  final List<String> assignedIds = [];

  void addToResort(String propertyId, MaintenanceIssue issue) {
    store.add(issue);
    _propertyIdByIssueId[issue.id] = propertyId;
  }

  @override
  Future<String> uploadPhoto({
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<MaintenanceIssue> report({
    required String reservationId,
    required MaintenanceCategory category,
    String description = '',
    String? photoUrl,
    MaintenancePriority priority = MaintenancePriority.medium,
  }) async =>
      throw UnimplementedError('admin never reports a maintenance issue');

  @override
  Future<List<MaintenanceIssue>> myIssues(String reservationId) async =>
      throw UnimplementedError('not used by this screen');

  @override
  Future<List<MaintenanceIssue>> list({
    required String propertyId,
    String? assignedStaffId,
    MaintenanceStatus? status,
  }) async {
    listedPropertyIds.add(propertyId);
    return store.where((i) {
      if (_propertyIdByIssueId[i.id] != propertyId) return false;
      if (assignedStaffId != null && i.assignedStaffId != assignedStaffId) return false;
      if (status != null && i.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> assign({required String id, required String staffId}) async {
    assignedIds.add(id);
    final i = store.indexWhere((issue) => issue.id == id);
    final existing = store[i];
    store[i] = MaintenanceIssue(
      id: existing.id,
      reservationId: existing.reservationId,
      category: existing.category,
      description: existing.description,
      photoUrl: existing.photoUrl,
      priority: existing.priority,
      status: existing.status,
      assignedStaffId: staffId,
      assignedStaffName: existing.assignedStaffName,
      createdAt: existing.createdAt,
    );
  }

  @override
  Future<void> updateStatus({
    required String id,
    required MaintenanceStatus status,
  }) async {
    final i = store.indexWhere((issue) => issue.id == id);
    final existing = store[i];
    store[i] = MaintenanceIssue(
      id: existing.id,
      reservationId: existing.reservationId,
      category: existing.category,
      description: existing.description,
      photoUrl: existing.photoUrl,
      priority: existing.priority,
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

Widget _appFor(FakeMaintenanceRepository repo) => ProviderScope(
      overrides: [
        maintenanceRepositoryProvider.overrideWithValue(repo),
        rosterOverride,
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: const MaterialApp(home: MaintenanceIssuesScreen()),
    );

void main() {
  testWidgets('shows an empty state when no issues match', (tester) async {
    await tester.pumpWidget(_appFor(FakeMaintenanceRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No issues match this filter'), findsOneWidget);
  });

  testWidgets('lists an existing issue with its category and priority', (
    tester,
  ) async {
    final repo = FakeMaintenanceRepository()
      ..addToResort('p1', const MaintenanceIssue(
        id: 'i1',
        reservationId: 'res-1',
        category: MaintenanceCategory.ac,
        description: 'AC not cooling',
        priority: MaintenancePriority.high,
        status: MaintenanceStatus.reported,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('AC'), findsOneWidget);
    expect(find.text('AC not cooling'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
  });

  // Review Focus #1: a person with memberships at two resorts must never
  // see resort B's rows while working in resort A.
  testWidgets(
      'MaintenanceRepository.list: rows from another resort never reach '
      'the screen', (tester) async {
    final repo = FakeMaintenanceRepository()
      ..addToResort('p1', const MaintenanceIssue(
        id: 'i1',
        reservationId: 'res-1',
        category: MaintenanceCategory.ac,
        description: 'Resort A issue',
        priority: MaintenancePriority.medium,
        status: MaintenanceStatus.reported,
      ))
      ..addToResort('p2', const MaintenanceIssue(
        id: 'i2',
        reservationId: 'res-2',
        category: MaintenanceCategory.plumbing,
        description: 'Resort B issue',
        priority: MaintenancePriority.medium,
        status: MaintenanceStatus.reported,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Resort A issue'), findsOneWidget);
    expect(find.text('Resort B issue'), findsNothing);
    expect(repo.listedPropertyIds, everyElement('p1'));
  });

  // Final review C1: "Assign to" lists `list_resort_members` for the current
  // resort only -- never another resort's staff.
  testWidgets("the assign-to picker lists only the current resort's members",
      (tester) async {
    final repo = FakeMaintenanceRepository()
      ..addToResort('p1', const MaintenanceIssue(
        id: 'i1',
        reservationId: 'res-1',
        category: MaintenanceCategory.ac,
        description: 'AC not cooling',
        priority: MaintenancePriority.high,
        status: MaintenanceStatus.reported,
      ));
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();

    expect(find.text('Sita Staff'), findsWidgets);
    expect(find.text('Olga Otherresort'), findsNothing);
  });
}

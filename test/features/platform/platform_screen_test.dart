import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/format.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';

class FakePlatformRepository implements PlatformSource {
  List<ResortSummary> store = [];
  final List<(String, String)> statusCalls = [];
  final List<(String, String)> createCalls = [];
  int _idCounter = 0;

  @override
  Future<List<ResortSummary>> resorts() async => store;

  @override
  Future<void> setStatus(String propertyId, String status) async {
    statusCalls.add((propertyId, status));
    final i = store.indexWhere((r) => r.propertyId == propertyId);
    if (i >= 0) {
      final old = store[i];
      store[i] = ResortSummary(
        propertyId: old.propertyId,
        name: old.name,
        status: status,
        ownerEmails: old.ownerEmails,
        createdAt: old.createdAt,
        bookings30d: old.bookings30d,
        revenue30d: old.revenue30d,
        bookings365d: old.bookings365d,
        revenue365d: old.revenue365d,
      );
    }
  }

  @override
  Future<String> createResort(String name, String ownerEmail) async {
    createCalls.add((name, ownerEmail));
    final id = 'resort-${_idCounter++}';
    store = [
      ...store,
      ResortSummary(
        propertyId: id,
        name: name,
        status: 'active',
        ownerEmails: [ownerEmail],
        createdAt: DateTime.now(),
        bookings30d: 0,
        revenue30d: 0,
        bookings365d: 0,
        revenue365d: 0,
      ),
    ];
    return id;
  }
}

final _resortA = ResortSummary(
  propertyId: 'p1',
  name: 'Resort A',
  status: 'active',
  ownerEmails: const ['ownera@x.com'],
  createdAt: DateTime(2024, 1, 1),
  bookings30d: 5,
  revenue30d: 12000,
  bookings365d: 60,
  revenue365d: 140000,
);

final _resortB = ResortSummary(
  propertyId: 'p2',
  name: 'Resort B',
  status: 'suspended',
  ownerEmails: const ['ownerb@x.com'],
  createdAt: DateTime(2024, 2, 1),
  bookings30d: 0,
  revenue30d: 0,
  bookings365d: 10,
  revenue365d: 20000,
);

Widget _appFor(FakePlatformRepository repo) => ProviderScope(
      overrides: [platformSourceProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: PlatformScreen()),
    );

void main() {
  testWidgets('renders two resorts from a fake', (tester) async {
    final repo = FakePlatformRepository()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Resort A'), findsOneWidget);
    expect(find.text('Resort B'), findsOneWidget);
    expect(find.textContaining('ownera@x.com'), findsOneWidget);
    expect(find.textContaining('ownerb@x.com'), findsOneWidget);
    expect(find.textContaining(formatInr(12000)), findsOneWidget);
  });

  testWidgets('tapping Suspend then confirming calls setStatus(id, suspended)', (
    tester,
  ) async {
    final repo = FakePlatformRepository()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
    await tester.pumpAndSettle();

    // Confirmation dialog is up; confirm it.
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();

    expect(repo.statusCalls, [('p1', 'suspended')]);
  });

  testWidgets('creating a resort calls createResort and refreshes the list', (
    tester,
  ) async {
    final repo = FakePlatformRepository()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('new-resort-name')), 'Resort E');
    await tester.enterText(
        find.byKey(const Key('new-resort-owner-email')), 'owner@x.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(repo.createCalls, [('Resort E', 'owner@x.com')]);
    expect(find.text('Resort E'), findsOneWidget);
  });
}

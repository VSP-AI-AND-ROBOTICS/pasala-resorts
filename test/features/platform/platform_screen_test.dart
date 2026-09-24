import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/format.dart';
import 'package:pasala/core/theme/app_theme.dart';
import 'package:pasala/core/theme/theme_toggle_button.dart';
import 'package:pasala/data/repositories/platform_repository.dart';
import 'package:pasala/features/platform/platform_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final _resortC = ResortSummary(
  propertyId: 'p3',
  name: 'Resort C',
  status: 'archived',
  ownerEmails: const ['ownerc@x.com'],
  createdAt: DateTime(2024, 3, 1),
  bookings30d: 0,
  revenue30d: 0,
  bookings365d: 0,
  revenue365d: 0,
);

Widget _appFor(
  FakePlatformRepository repo, {
  ThemeMode themeMode = ThemeMode.light,
}) => ProviderScope(
  overrides: [platformSourceProvider.overrideWithValue(repo)],
  child: MaterialApp(
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: themeMode,
    home: const PlatformScreen(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets(
    'tapping Suspend then confirming calls setStatus(id, suspended)',
    (tester) async {
      final repo = FakePlatformRepository()..store = [_resortA, _resortB];
      await tester.pumpWidget(_appFor(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('resort-status-btn-p1')));
      await tester.pumpAndSettle();

      // Confirmation dialog is up; confirm it.
      await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
      await tester.pumpAndSettle();

      expect(repo.statusCalls, [('p1', 'suspended')]);
    },
  );

  testWidgets('creating a resort calls createResort and refreshes the list', (
    tester,
  ) async {
    final repo = FakePlatformRepository()..store = [_resortA, _resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('new-resort-name')),
      'Resort E',
    );
    await tester.enterText(
      find.byKey(const Key('new-resort-owner-email')),
      'owner@x.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(repo.createCalls, [('Resort E', 'owner@x.com')]);
    expect(find.text('Resort E'), findsOneWidget);
  });

  testWidgets('a suspended resort offers Reactivate, which sets it active', (
    tester,
  ) async {
    final repo = FakePlatformRepository()..store = [_resortB];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Reactivate'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resort-status-btn-p2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivate'));
    await tester.pumpAndSettle();

    expect(repo.statusCalls, [('p2', 'active')]);
  });

  // Final review F3: an archived resort is not active, so it must not offer
  // "Suspend" as if it were; it shows its status and no action at all.
  testWidgets('an archived resort shows its status and no status action', (
    tester,
  ) async {
    final repo = FakePlatformRepository()..store = [_resortC];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsOneWidget);
    expect(find.byKey(const Key('resort-status-btn-p3')), findsNothing);
    expect(find.text('Suspend'), findsNothing);
    expect(find.text('Reactivate'), findsNothing);
  });

  testWidgets('shows the theme toggle in the platform app bar', (tester) async {
    final repo = FakePlatformRepository()..store = [_resortA];
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    expect(find.byType(ThemeToggleButton), findsOneWidget);
  });

  testWidgets('renders in ThemeMode.dark without throwing', (tester) async {
    final repo = FakePlatformRepository()
      ..store = [_resortA, _resortB, _resortC];
    await tester.pumpWidget(_appFor(repo, themeMode: ThemeMode.dark));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Resort A'), findsOneWidget);
  });
}

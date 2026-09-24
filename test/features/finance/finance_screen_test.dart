import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_collections_tab.dart';
import 'package:pasala/features/finance/finance_screen.dart';
import 'package:pasala/features/finance/providers.dart';

import '../../support/fake_finance_source.dart';

const _resort = ResortMembership(
    propertyId: 'p1', resortName: 'Resort R', role: ResortRole.accountant);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

final _august =
    DateTimeRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31));
final _augustFilter =
    (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31), propertyId: 'p1');

/// Records every file handed to the downloader; answers [delivers].
class _Downloads {
  _Downloads({this.delivers = true});
  final bool delivers;
  final files = <(String, String)>[];

  bool download(String filename, String csv) {
    files.add((filename, csv));
    return delivers;
  }
}

/// A phone is 420 wide (below the 840 breakpoint); both sizes are tall
/// enough that every card of a list is built.
Future<void> _pump(
  WidgetTester tester,
  FakeFinanceSource source, {
  bool wide = false,
  _Downloads? downloads,
  bool settle = true,
}) async {
  tester.view.physicalSize = wide ? const Size(1400, 1400) : const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      csvDownloaderProvider.overrideWithValue((downloads ?? _Downloads()).download),
    ],
    child: MaterialApp(home: FinanceScreen(initialRange: _august)),
  ));
  if (settle) await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await tester.pumpAndSettle();
}

Finder _inKey(String key, String text) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text));

final _augustRows = [
  collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
  collectionRow(day: DateTime(2026, 8, 5), source: CollectionSource.refund, amount: -1500),
  collectionRow(
      day: DateTime(2026, 8, 10),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.walkInSale,
      method: PaymentMethod.cash,
      txnCount: 2,
      amount: 550),
  collectionRow(
      day: DateTime(2026, 8, 10),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.walkInSale,
      method: PaymentMethod.upi,
      amount: 300),
  collectionRow(
      day: DateTime(2026, 8, 12),
      channel: CollectionChannel.frontDesk,
      source: CollectionSource.checkoutBalance,
      method: PaymentMethod.cash,
      amount: 7540),
];

void main() {
  group('Today', () {
    testWidgets("shows the day's figures of the current resort", (tester) async {
      final source = FakeFinanceSource()
        ..summaryValue = financeSummary(
          online: 1000,
          desk: {PaymentMethod.cash: 2800, PaymentMethod.card: 120},
          refunds: 600,
          roomTax: 240,
          inHouseCount: 1,
          inHouseBalance: 1200,
        );
      await _pump(tester, source);

      expect(find.text('Today, 25 Sep 2026'), findsOneWidget);
      expect(_inKey('today-online', '₹1,000.00'), findsOneWidget);
      expect(_inKey('today-desk', '₹2,920.00'), findsOneWidget);
      expect(_inKey('today-desk', 'Cash ₹2,800.00'), findsOneWidget);
      expect(_inKey('today-desk', 'Card ₹120.00'), findsOneWidget);
      expect(_inKey('today-refunds', '₹600.00'), findsOneWidget);
      expect(_inKey('today-net', '₹3,320.00'), findsOneWidget);
      expect(_inKey('today-room-tax', '₹240.00'), findsOneWidget);
      expect(_inKey('today-in-house', '1'), findsOneWidget);
      expect(_inKey('today-in-house', 'Unpaid balance ₹1,200.00'), findsOneWidget);
      expect(source.summaryCalls, isNotEmpty);
      expect(source.summaryCalls, everyElement('p1'));
      // Today is always the resort's today: no range to pick.
      expect(find.byKey(const Key('finance-range')), findsNothing);
    });

    testWidgets('a failed load goes through FailureView', (tester) async {
      await _pump(tester, FakeFinanceSource()..summaryError = const NetworkFailure());

      expect(find.text('Cannot reach the server. Check your connection.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('pull to refresh fetches the summary again', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      final before = source.summaryCalls.length;

      // The drag distance a RefreshIndicator needs to arm scales with the
      // scrollable's viewport height (25% of it); at this tall physical
      // size that is ~600px, so the offset must clear that, not just be
      // "a swipe".
      await tester.fling(find.byType(ListView), const Offset(0, 900), 1000);
      await tester.pumpAndSettle();

      expect(source.summaryCalls.length, greaterThan(before));
    });
  });

  group('Collections', () {
    testWidgets('asks for the chosen range of the current resort', (tester) async {
      final source = FakeFinanceSource();
      await _pump(tester, source);
      await _openTab(tester, 'Collections');

      expect(source.collectionsCalls, isNotEmpty);
      expect(source.collectionsCalls, everyElement(_augustFilter));
      expect(find.text('1 Aug 2026 – 31 Aug 2026'), findsOneWidget);
    });

    testWidgets('a phone shows one card per day and a totals card', (tester) async {
      await _pump(tester, FakeFinanceSource()..collectionRows = _augustRows);
      await _openTab(tester, 'Collections');

      expect(_inKey('collections-2026-08-01', 'Online ₹5,000.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'Cash ₹550.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'UPI ₹300.00'), findsOneWidget);
      expect(_inKey('collections-2026-08-10', 'Net ₹850.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Online ₹5,000.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Cash ₹8,090.00'), findsOneWidget);
      expect(_inKey('collections-total', 'Net ₹11,890.00'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('collections-2026-08-05')),
              matching: find.textContaining(RegExp(r'^Refunds .*1,500\.00$'))),
          findsOneWidget);
    });

    testWidgets('a wide screen shows a table with a Total row', (tester) async {
      await _pump(tester, FakeFinanceSource()..collectionRows = _augustRows, wide: true);
      await _openTab(tester, 'Collections');

      expect(find.byKey(const Key('collections-table')), findsOneWidget);
      for (final header in ['Date', 'Online', 'Cash', 'Card', 'UPI', 'Bank', 'Other', 'Refunds', 'Net']) {
        expect(find.text(header), findsWidgets, reason: header);
      }
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹11,890.00'), findsOneWidget);
    });

    testWidgets('no collections shows an empty state', (tester) async {
      await _pump(tester, FakeFinanceSource());
      await _openTab(tester, 'Collections');

      expect(find.text('No collections in this period'), findsOneWidget);
    });

    testWidgets('pull to refresh fetches collections again', (tester) async {
      final source = FakeFinanceSource()..collectionRows = _augustRows;
      await _pump(tester, source);
      await _openTab(tester, 'Collections');
      final before = source.collectionsCalls.length;

      await tester.fling(
          find.descendant(
              of: find.byType(FinanceCollectionsTab), matching: find.byType(ListView)),
          const Offset(0, 900),
          1000);
      await tester.pumpAndSettle();

      expect(source.collectionsCalls.length, greaterThan(before));
    });
  });

  group('Export', () {
    testWidgets('Collections exports the resort header, then one line per row',
        (tester) async {
      final downloads = _Downloads();
      await _pump(
          tester, FakeFinanceSource()..collectionRows = [collectionRow(amount: 5000)],
          downloads: downloads);
      await _openTab(tester, 'Collections');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-collections-2026-08-01-2026-08-31.csv');
      expect(
          csv,
          'Resort R,GSTIN 29ABCDE1234F1Z5\r\n'
          'Period,2026-08-01,2026-08-31\r\n'
          'Date,Channel,Source,Method,Transactions,Amount\r\n'
          '2026-08-01,online,booking_advance,gateway,1,5000.00\r\n');
      expect(find.text('CSV exported.'), findsOneWidget);
    });

    testWidgets("Today exports under the resort's today", (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource(), downloads: downloads);

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      final (name, csv) = downloads.files.single;
      expect(name, 'fin-r-today-2026-09-25-2026-09-25.csv');
      expect(csv, startsWith('Resort R,GSTIN 29ABCDE1234F1Z5\r\nPeriod,2026-09-25,2026-09-25\r\n'));
      expect(csv, contains('Net collected,0.00\r\n'));
    });

    testWidgets('a platform without downloads says so', (tester) async {
      await _pump(tester, FakeFinanceSource(), downloads: _Downloads(delivers: false));

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text("CSV export isn't available on this platform yet."), findsOneWidget);
    });

    // Review Focus 5.
    testWidgets('Export before the report has loaded says so and writes nothing',
        (tester) async {
      final source = FakeFinanceSource()..hold = Completer<void>();
      final downloads = _Downloads();
      await _pump(tester, source, downloads: downloads, settle: false);
      await tester.pump();

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text('Still loading -- try again in a moment.'), findsOneWidget);
      expect(downloads.files, isEmpty);
      source.hold!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Export after a failed load says so and writes nothing',
        (tester) async {
      final downloads = _Downloads();
      await _pump(tester, FakeFinanceSource()..collectionsError = const NetworkFailure(),
          downloads: downloads);
      await _openTab(tester, 'Collections');

      await tester.tap(find.byKey(const Key('finance-export')));
      await tester.pump();

      expect(find.text("This report didn't load, so there is nothing to export."), findsOneWidget);
      expect(downloads.files, isEmpty);
    });
  });
}

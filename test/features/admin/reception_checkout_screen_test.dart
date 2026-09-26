import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/admin/desk_invoice.dart';
import 'package:pasala/features/admin/reception_checkout_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

const _resort =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

Reservation _checkedIn(String id, {String? customerName}) => Reservation(
      id: id,
      unitId: 'u1',
      start: DateTime(2026, 9, 1),
      end: DateTime(2026, 9, 3),
      kind: ReservationKind.booking,
      status: ReservationStatus.checkedIn,
      customerName: customerName,
      guests: 2,
    );

final listedPropertyIds = <String>[];

Widget _appFor(List<Reservation> guests) {
  final router = GoRouter(
    initialLocation: '/admin/check-out',
    routes: [
      GoRoute(
          path: '/admin/check-out',
          builder: (_, _) => const ReceptionCheckoutScreen()),
      GoRoute(
          path: '/admin/check-out/:reservationId',
          builder: (_, _) => const Text('CHECKOUT SCREEN')),
    ],
  );
  return ProviderScope(
    overrides: [
      checkedInProvider.overrideWith((ref, propertyId) async {
        listedPropertyIds.add(propertyId);
        return guests;
      }),
      currentResortProvider.overrideWith(_FixedResort.new),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

typedef _Harness = ({Widget app, GoRouter router});

/// The check-out list at [location] (e.g. `/admin/check-out?checkedOut=r1`),
/// routed like `router.dart` does, with [download] as the invoice seam.
_Harness _appAt(
  String location, {
  List<Reservation> guests = const [],
  DeskInvoiceDownload? download,
}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/admin/check-out',
        builder: (_, state) => ReceptionCheckoutScreen(
          checkedOutId: state.uri.queryParameters[checkedOutParam],
        ),
      ),
    ],
  );
  return (
    app: ProviderScope(
      overrides: [
        checkedInProvider.overrideWith((ref, propertyId) async => guests),
        currentResortProvider.overrideWith(_FixedResort.new),
        deskInvoiceDownloadProvider.overrideWithValue(download),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
    router: router,
  );
}

Future<void> _noop(BuildContext _, WidgetRef _, String _) async {}

void main() {
  testWidgets('shows an empty state when no guests are checked in',
      (tester) async {
    await tester.pumpWidget(_appFor(const []));
    await tester.pumpAndSettle();

    expect(find.text('No guests currently checked in'), findsOneWidget);
  });

  testWidgets('lists every checked-in guest with a Check Out action',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Check Out'), findsOneWidget);
    // Review Focus #1: the screen must pass the current resort's id
    // through to the repository, not rely on RLS alone.
    expect(listedPropertyIds, everyElement('p1'));
  });

  testWidgets('tapping Check Out navigates to the checkout screen',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: 'Ravi Kumar')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(find.text('CHECKOUT SCREEN'), findsOneWidget);
  });

  // I9: the checkedIn() repository query never embedded the guest's
  // profile, so this screen's `g.customerName ?? 'Guest'` fallback always
  // fired -- reception could not tell which checked-in guest was which by
  // name. This widget test alone can't catch that (it feeds a Reservation
  // with the name already attached, bypassing the repository), but it
  // locks in the fallback still behaves correctly when a name is genuinely
  // absent, now that the common case is fixed at the repository level in
  // stay_repository.dart.
  testWidgets('falls back to "Guest" only when no name is available',
      (tester) async {
    await tester.pumpWidget(
      _appFor([_checkedIn('r1', customerName: null)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Guest'), findsOneWidget);
  });

  // E2E bug (e2e/tests/frontdesk.spec.ts): `context.push` never reaches the
  // browser's address bar (go_router reports only declarative locations to
  // the platform), so the URL stayed at /admin/check-out and a reload lost
  // the checkout. The URL the router reports must carry the booking id.
  testWidgets('Check Out puts the booking id in the browser URL, and back '
      'returns to the list', (tester) async {
    final router = GoRouter(
      initialLocation: '/admin/check-out',
      routes: [
        GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen(),
            routes: [
              GoRoute(
                  path: ':reservationId',
                  builder: (_, _) => const Text('CHECKOUT SCREEN')),
            ]),
      ],
    );
    addTearDown(router.dispose);
    Uri browserUrl() => router.routeInformationParser
        .restoreRouteInformation(router.routerDelegate.currentConfiguration)!
        .uri;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        checkedInProvider.overrideWith(
            (ref, propertyId) async => [_checkedIn('r1', customerName: 'Ravi Kumar')]),
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(find.text('CHECKOUT SCREEN'), findsOneWidget);
    expect(browserUrl().path, '/admin/check-out/r1');

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(browserUrl().path, '/admin/check-out');
  });

  // The desk checkout is addressed by its URL alone -- a route `extra`
  // does not survive a web refresh or back/forward.
  testWidgets('Check Out opens the desk checkout for that booking by URL',
      (tester) async {
    String? location;
    Object? extra;
    final router = GoRouter(
      initialLocation: '/admin/check-out',
      routes: [
        GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen(),
            routes: [
              GoRoute(
                  path: ':reservationId',
                  builder: (_, state) {
                    location = state.matchedLocation;
                    extra = state.extra;
                    return const Text('CHECKOUT SCREEN');
                  }),
            ]),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        checkedInProvider.overrideWith(
            (ref, propertyId) async => [_checkedIn('r1', customerName: 'Ravi Kumar')]),
        currentResortProvider.overrideWith(_FixedResort.new),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Check Out'));
    await tester.pumpAndSettle();

    expect(location, '/admin/check-out/r1');
    expect(extra, isNull);
  });

  group('after a desk checkout', () {
    const id = 'abcdef12-3456-4000-8000-000000000001';
    const second = '99887766-3456-4000-8000-000000000002';
    final downloadButton = find.byKey(const Key('desk-invoice-download'));

    test('deskCheckoutDoneLocation encodes the id', () {
      expect(deskCheckoutDoneLocation('r1'), '/admin/check-out?checkedOut=r1');
      expect(deskCheckoutDoneLocation('a&b'),
          '/admin/check-out?checkedOut=a%26b');
    });

    testWidgets('no banner without a checked-out booking, or with a blank one',
        (tester) async {
      for (final location in [
        '/admin/check-out',
        '/admin/check-out?checkedOut=',
        '/admin/check-out?checkedOut=%20',
      ]) {
        final h = _appAt(location, download: _noop);
        addTearDown(h.router.dispose);
        await tester.pumpWidget(h.app);
        await tester.pumpAndSettle();
        expect(find.text('Guest checked out'), findsNothing, reason: location);
      }
    });

    testWidgets('shows the success banner above the remaining guests',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          guests: [_checkedIn('r2', customerName: 'Meera Nair')],
          download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desk-checkout-done')), findsOneWidget);
      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('Booking abcdef12 is settled.'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);
      expect(find.text('Meera Nair'), findsOneWidget);
    });

    testWidgets('shows above the empty state when the last guest has left',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('No guests currently checked in'), findsOneWidget);
    });

    testWidgets('Download invoice passes the booking id once and shows progress',
        (tester) async {
      final calls = <String>[];
      final pending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, reservationId) {
        calls.add(reservationId);
        return pending.future;
      });
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      expect(find.text('Preparing invoice…'), findsOneWidget);
      expect(tester.widget<TextButton>(downloadButton).enabled, isFalse);

      await tester.tap(downloadButton, warnIfMissed: false);
      await tester.pump();
      expect(calls, [id]);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Download invoice'), findsOneWidget);
      expect(tester.widget<TextButton>(downloadButton).enabled, isTrue);
    });

    testWidgets('without the invoice PDF feature there is no download button',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id');
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsOneWidget);
      expect(downloadButton, findsNothing);
    });

    testWidgets('a refused download shows readable copy and keeps the banner',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) async => throw PostgrestException(
              message: 'resort_mismatch', code: 'P0021'));
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(find.text('That belongs to a different resort.'), findsOneWidget);
      expect(find.textContaining('resort_mismatch'), findsNothing);
      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);
    });

    testWidgets('any other failure shows the generic message', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) async =>
              throw StateError('printing plugin exploded'));
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('Dismiss clears the banner and the URL', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsNothing);
      expect(h.router.routerDelegate.currentConfiguration.uri.toString(),
          '/admin/check-out');
    });

    // Review Focus 1.
    testWidgets('a second checkout replaces the banner and resets it',
        (tester) async {
      final calls = <String>[];
      final firstPending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, reservationId) {
        calls.add(reservationId);
        return calls.length == 1 ? firstPending.future : Future.value();
      });
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      expect(find.text('Preparing invoice…'), findsOneWidget);

      h.router.go(deskCheckoutDoneLocation(second));
      await tester.pumpAndSettle();
      expect(find.text('Booking 99887766 is settled.'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();
      expect(calls, [id, second]);

      firstPending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Review Focus 2.
    testWidgets('dismissing while the invoice is still being prepared is safe',
        (tester) async {
      final pending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) => pending.future);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      pending.completeError(StateError('late failure'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Something went wrong.'), findsNothing);
      expect(find.text('Guest checked out'), findsNothing);
    });

    // Review Focus 3.
    testWidgets('a short id in the URL is shown whole', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=abc', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Booking abc is settled.'), findsOneWidget);
    });
  });
}

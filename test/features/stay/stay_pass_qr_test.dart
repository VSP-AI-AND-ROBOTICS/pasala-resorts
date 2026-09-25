import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/repositories/stay_pass_repository.dart';
import 'package:pasala/features/stay/stay_pass_qr.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../support/fake_stay_pass_source.dart';

const _id = '3f2a1b9c-0000-0000-0000-000000000000';

Widget _host(FakeStayPassSource passes, Widget child) => ProviderScope(
      retry: (_, _) => null,
      overrides: [stayPassSourceProvider.overrideWithValue(passes)],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('shows the pass as a QR with the booking code under it',
      (tester) async {
    final passes = FakeStayPassSource();
    await tester.pumpWidget(_host(passes, const StayPassQr(reservationId: _id)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.byKey(const Key('stay-pass-qr')), findsOneWidget);
    expect(find.text('Booking code PR3F2A'), findsOneWidget);
    expect(passes.issueCalls, [_id]);
  });

  // Review Focus 4: offline, or a booking not confirmed yet.
  testWidgets('a pass that fails to load shows the booking code and retries',
      (tester) async {
    final passes = FakeStayPassSource()..issueError = const NetworkFailure();
    await tester.pumpWidget(_host(passes, const StayPassQr(reservationId: _id)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text("Couldn't load your pass. Show the booking code at the desk."),
        findsOneWidget);
    expect(find.text('Booking code PR3F2A'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    passes.issueError = null;
    await tester.tap(find.byKey(const Key('stay-pass-retry')));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(passes.issueCalls, [_id, _id]);
  });

  testWidgets('the compact form shows only the QR', (tester) async {
    await tester.pumpWidget(_host(FakeStayPassSource(),
        const StayPassQr(reservationId: _id, size: 64, compact: true)));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Booking code'), findsNothing);
  });

  testWidgets('the thumbnail opens the pass full size, and Close closes it',
      (tester) async {
    await tester.pumpWidget(
        _host(FakeStayPassSource(), const StayPassThumbnail(reservationId: _id)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('stay-pass-thumbnail')));
    await tester.pumpAndSettle();

    expect(find.text('Check-in pass'), findsOneWidget);
    expect(find.byType(QrImageView), findsNWidgets(2));
    expect(find.text('Booking code PR3F2A'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Check-in pass'), findsNothing);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/features/booking/quote_sheet.dart';

void main() {
  final quote = Quote.fromJson(const {
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {'date': '2026-08-03', 'label': 'Weekend rate', 'amount': 12000,
       'extra_guests': 2, 'extra_guest_amount': 3000},
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'total': 16500,
  });

  final couponedQuote = Quote.fromJson(const {
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {'date': '2026-08-03', 'label': 'Weekend rate', 'amount': 12000,
       'extra_guests': 2, 'extra_guest_amount': 3000},
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'coupon': {'code': 'SAVE10', 'kind': 'percent', 'value': 10, 'discount': 1650},
    'total': 14850,
  });

  Widget sheet({
    required Quote quote,
    bool busy = false,
    Future<void> Function(String code)? onApplyCoupon,
    bool couponBusy = false,
    String? couponError,
    VoidCallback? onPay,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: QuoteSheet(
            quote: quote,
            busy: busy,
            onPay: onPay ?? () {},
            onApplyCoupon: onApplyCoupon ?? (_) async {},
            couponBusy: couponBusy,
            couponError: couponError,
          ),
        ),
      );

  testWidgets('renders the server total verbatim', (tester) async {
    await tester.pumpWidget(sheet(quote: quote));

    expect(find.text('₹16,500'), findsOneWidget);
    expect(find.text('Weekend rate'), findsOneWidget);
    expect(find.textContaining('Cleaning'), findsOneWidget);
  });

  testWidgets('the pay button is disabled while busy', (tester) async {
    await tester.pumpWidget(sheet(quote: quote, busy: true));

    final button = tester.widget<FilledButton>(
        find.byKey(const Key('pay-button')));
    expect(button.onPressed, isNull);
  });

  testWidgets('no coupon applied means no discount row is shown',
      (tester) async {
    await tester.pumpWidget(sheet(quote: quote));

    expect(find.byKey(const Key('coupon-discount-row')), findsNothing);
  });

  testWidgets(
      'tapping Apply calls onApplyCoupon with the trimmed field text',
      (tester) async {
    final applied = <String>[];
    await tester.pumpWidget(sheet(
      quote: quote,
      onApplyCoupon: (code) async => applied.add(code),
    ));

    await tester.enterText(find.byKey(const Key('coupon-field')), '  SAVE10  ');
    await tester.tap(find.byKey(const Key('apply-coupon-button')));
    await tester.pump();

    expect(applied, ['SAVE10']);
  });

  testWidgets(
      'on success the sheet re-renders with a discount line and the new '
      'total', (tester) async {
    await tester.pumpWidget(sheet(quote: couponedQuote));

    expect(find.byKey(const Key('coupon-discount-row')), findsOneWidget);
    expect(find.textContaining('SAVE10'), findsOneWidget);
    expect(find.text('-₹1,650'), findsOneWidget);
    expect(find.text('₹14,850'), findsOneWidget);
  });

  testWidgets(
      'on failure the message shows inline and the previous (uncouponed) '
      'quote stays -- Pay is still usable', (tester) async {
    await tester.pumpWidget(sheet(
      quote: quote, // the PREVIOUS quote -- unchanged despite the failure
      couponError: 'coupon NOPE not found or inactive',
    ));

    expect(find.byKey(const Key('coupon-error')), findsOneWidget);
    expect(find.text('coupon NOPE not found or inactive'), findsOneWidget);
    // The previous quote's total is still what's shown -- a failed apply
    // never touched it.
    expect(find.text('₹16,500'), findsOneWidget);
    expect(find.byKey(const Key('coupon-discount-row')), findsNothing);

    final payButton = tester.widget<FilledButton>(
        find.byKey(const Key('pay-button')));
    expect(payButton.onPressed, isNotNull,
        reason: 'the customer can continue without the coupon');
  });

  testWidgets('the Apply button is disabled while a coupon apply is in '
      'flight', (tester) async {
    await tester.pumpWidget(sheet(quote: quote, couponBusy: true));

    final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('apply-coupon-button')));
    expect(button.onPressed, isNull);
  });
}

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

  final taxedQuote = Quote.fromJson(const {
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {'date': '2026-08-03', 'label': 'Weekend rate', 'amount': 12000,
       'extra_guests': 2, 'extra_guest_amount': 3000},
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'tax_pct': 18,
    'tax_amount': 2970,
    'total': 19470,
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
    num advancePct = 100,
    void Function(num amount, bool isSplit)? onPaySplit,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: QuoteSheet(
            quote: quote,
            busy: busy,
            advancePct: advancePct,
            onPay: onPay ?? () {},
            onPaySplit: onPaySplit,
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

  testWidgets('a zero-tax property (the default) shows no tax row',
      (tester) async {
    await tester.pumpWidget(sheet(quote: quote));

    expect(find.byKey(const Key('tax-row')), findsNothing);
  });

  testWidgets('a nonzero tax_pct renders a tax row with the percentage, '
      'the tax amount, and the tax-inclusive total', (tester) async {
    await tester.pumpWidget(sheet(quote: taxedQuote));

    expect(find.byKey(const Key('tax-row')), findsOneWidget);
    expect(find.textContaining('Tax (18%)'), findsOneWidget);
    expect(find.text('₹2,970'), findsOneWidget);
    expect(find.text('₹19,470'), findsOneWidget);
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

  testWidgets('offers 35% advance deposit option when advancePct < 100',
      (tester) async {
    num? paidAmount;
    bool? wasSplit;

    await tester.pumpWidget(sheet(
      quote: quote, // ₹16,500 total
      advancePct: 35,
      onPaySplit: (amount, split) {
        paidAmount = amount;
        wasSplit = split;
      },
    ));

    expect(find.byKey(const Key('pay-split-radio')), findsOneWidget);
    expect(find.byKey(const Key('pay-full-radio')), findsOneWidget);
    expect(find.textContaining('35% advance now'), findsOneWidget);

    // Tap the split payment radio option
    await tester.tap(find.byKey(const Key('pay-split-radio')));
    await tester.pumpAndSettle();

    // Tap Pay button
    await tester.tap(find.byKey(const Key('pay-button')));
    await tester.pumpAndSettle();

    // 16500 * 0.35 = 5775
    expect(paidAmount, equals(5775.0));
    expect(wasSplit, isTrue);
  });

  testWidgets('rounds a fractional advance up so confirm_booking accepts it',
      (tester) async {
    num? paidAmount;

    await tester.pumpWidget(sheet(
      quote: quote, // ₹16,500 total
      advancePct: 33.33,
      onPaySplit: (amount, _) => paidAmount = amount,
    ));

    await tester.tap(find.byKey(const Key('pay-split-radio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pay-button')));
    await tester.pumpAndSettle();

    // Server minimum is round(16500 * 33.33 / 100, 2) = 5499.45; rounding
    // to the nearest rupee (5499) would be rejected after the charge.
    expect(paidAmount, equals(5500.0));
    expect(find.textContaining('33.33% advance now'), findsOneWidget);
  });

  testWidgets('offers no split when the property requires full payment',
      (tester) async {
    await tester.pumpWidget(sheet(quote: quote, advancePct: 100));

    expect(find.byKey(const Key('pay-split-radio')), findsNothing);
  });
}

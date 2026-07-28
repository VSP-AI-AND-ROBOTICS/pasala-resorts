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

  testWidgets('renders the server total verbatim', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuoteSheet(quote: quote, busy: false, onPay: () {}),
      ),
    ));

    expect(find.text('₹16,500'), findsOneWidget);
    expect(find.text('Weekend rate'), findsOneWidget);
    expect(find.textContaining('Cleaning'), findsOneWidget);
  });

  testWidgets('the pay button is disabled while busy', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: QuoteSheet(quote: quote, busy: true, onPay: () {}),
      ),
    ));

    final button = tester.widget<FilledButton>(
        find.byKey(const Key('pay-button')));
    expect(button.onPressed, isNull);
  });
}

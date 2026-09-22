import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/quote.dart';

void main() {
  const json = {
    'unit_id': 'b1',
    'currency': 'INR',
    'guests': 6,
    'lines': [
      {
        'date': '2026-08-03',
        'label': 'Weekend rate',
        'amount': 12000,
        'rate_rule_id': 'r1',
        'extra_guests': 2,
        'extra_guest_amount': 3000,
      }
    ],
    'subtotal': 15000,
    'cleaning_fee': 1500,
    'total': 16500,
  };

  test('parses the server quote shape', () {
    final quote = Quote.fromJson(json);
    expect(quote.guests, 6);
    expect(quote.lines.single.date, DateTime.utc(2026, 8, 3));
    expect(quote.lines.single.label, 'Weekend rate');
    expect(quote.total, 16500);
  });

  test('total comes from the server, never recomputed', () {
    final quote = Quote.fromJson({...json, 'total': 99999});
    expect(quote.total, 99999);
  });

  test('coupon is null when the server omits it', () {
    final quote = Quote.fromJson(json);
    expect(quote.coupon, isNull);
  });

  test('taxPct/taxAmount default to 0 when the server omits them', () {
    final quote = Quote.fromJson(json);
    expect(quote.taxPct, 0);
    expect(quote.taxAmount, 0);
  });

  test('parses tax_pct/tax_amount when present', () {
    final quote = Quote.fromJson({
      ...json,
      'tax_pct': 18,
      'tax_amount': 2970,
      'total': 19470,
    });
    expect(quote.taxPct, 18);
    expect(quote.taxAmount, 2970);
    expect(quote.total, 19470);
  });

  test('parses an applied coupon', () {
    final quote = Quote.fromJson({
      ...json,
      'coupon': {
        'code': 'SAVE10',
        'kind': 'percent',
        'value': 10,
        'discount': 1150,
      },
      'total': 10350,
    });
    expect(quote.coupon, isNotNull);
    expect(quote.coupon!.code, 'SAVE10');
    expect(quote.coupon!.kind, 'percent');
    expect(quote.coupon!.value, 10);
    expect(quote.coupon!.discount, 1150);
    expect(quote.total, 10350);
  });
}

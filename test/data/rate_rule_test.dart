import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/rate_rule.dart';

void main() {
  test('maps the override kind to and from the database value', () {
    final rule = RateRule.fromJson(const {
      'id': 'r1',
      'unit_id': 'b1',
      'kind': 'override',
      'label': 'Diwali season',
      'price': 8100,
      'extra_guest_price': 800,
      'cleaning_fee': 600,
      'priority': 50,
      'valid_from': '2026-11-06',
      'valid_to': '2026-11-12',
      'weekdays': null,
    });

    expect(rule.kind, RateKind.override_);
    expect(rule.validFrom, DateTime.parse('2026-11-06'));
    expect(rule.toInsert()['kind'], 'override');
  });

  test('parses weekday arrays', () {
    final rule = RateRule.fromJson(const {
      'id': 'r2', 'unit_id': 'b1', 'kind': 'weekend', 'price': 6300,
      'extra_guest_price': 800, 'cleaning_fee': 600, 'priority': 10,
      'weekdays': [6, 7], 'valid_from': null, 'valid_to': null, 'label': null,
    });

    expect(rule.weekdays, [6, 7]);
    expect(rule.kind, RateKind.weekend);
  });
}

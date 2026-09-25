import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/current_charges.dart';

void main() {
  test('reads the tax inside food and activities', () {
    final charges = CurrentCharges.fromJson(const {
      'stay_amount': 5000,
      'food_amount': 630,
      'food_tax': 36.25,
      'activity_amount': 2360,
      'activity_tax': 360,
      'total': 7990,
      'paid': 0,
      'balance': 7990,
    });

    expect(charges.foodAmount, 630);
    expect(charges.foodTax, 36.25);
    expect(charges.activityAmount, 2360);
    expect(charges.activityTax, 360);
    expect(charges.total, 7990);
  });

  test('a server without the tax keys reads them as 0', () {
    final charges = CurrentCharges.fromJson(const {
      'stay_amount': 3000,
      'food_amount': 0,
      'activity_amount': 0,
      'total': 3000,
      'paid': 1000,
      'balance': 2000,
    });

    expect(charges.foodTax, 0);
    expect(charges.activityTax, 0);
  });
}

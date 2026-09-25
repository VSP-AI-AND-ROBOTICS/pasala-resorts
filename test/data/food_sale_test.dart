import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/food_sale.dart';
import 'package:pasala/data/models/payment_method.dart';

Map<String, dynamic> _row(Object? method) => {
      'id': 's1',
      'property_id': 'p1',
      'sale_date': '2026-08-10',
      'category': 'food',
      'item_name': 'Thali',
      'quantity': 2,
      'unit_price': 250,
      'amount': 500,
      'payment_method': method,
      'notes': null,
    };

void main() {
  test('reads the payment method from its wire value', () {
    expect(FoodSale.fromJson(_row('upi')).paymentMethod, PaymentMethod.upi);
    expect(FoodSale.fromJson(_row('bank_transfer')).paymentMethod, PaymentMethod.bankTransfer);
  });

  test('a missing or unknown method reads as Other', () {
    expect(FoodSale.fromJson(_row(null)).paymentMethod, PaymentMethod.other);
    expect(FoodSale.fromJson(_row('cheque')).paymentMethod, PaymentMethod.other);
  });

  test('a new sale defaults to Cash and is written as its wire value', () {
    final sale = FoodSale(
      id: '',
      propertyId: 'p1',
      saleDate: DateTime(2026, 8, 10),
      category: SaleCategory.food,
      itemName: 'Tea',
      quantity: 1,
      unitPrice: 50,
      amount: 50,
    );

    expect(sale.paymentMethod, PaymentMethod.cash);
    expect(sale.toInsert()['payment_method'], 'cash');
  });

  test('reads the tax the server stored on the sale', () {
    final sale = FoodSale.fromJson({..._row('cash'), 'tax_pct': 12, 'tax_amount': 22.5});

    expect(sale.taxPct, 12);
    expect(sale.taxAmount, 22.5);
  });

  test('a row without the tax keys reads them as 0, and tax is never sent', () {
    final sale = FoodSale.fromJson(_row('cash'));

    expect(sale.taxPct, 0);
    expect(sale.taxAmount, 0);
    expect(sale.toInsert().keys, isNot(contains('tax_pct')));
    expect(sale.toInsert().keys, isNot(contains('tax_amount')));
  });
}

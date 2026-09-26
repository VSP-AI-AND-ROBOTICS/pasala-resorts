import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_tables.dart';

import '../../support/fake_finance_source.dart';

void main() {
  group('collectionsByDay', () {
    final rows = [
      collectionRow(
          day: DateTime(2026, 8, 12),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.checkoutBalance,
          method: PaymentMethod.cash,
          amount: 7540),
      collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
      collectionRow(
          day: DateTime(2026, 8, 5),
          source: CollectionSource.refund,
          amount: -1500),
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
    ];

    test('one entry per day, oldest first', () {
      expect(collectionsByDay(rows).map((d) => d.day), [
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 5),
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 12),
      ]);
    });

    test('online, each desk method and refunds land in their own columns', () {
      final days = collectionsByDay(rows);

      expect(days[0].online, 5000);
      expect(days[1].refunds, -1500);
      expect(days[1].online, 0);
      expect(days[2].deskFor(PaymentMethod.cash), 550);
      expect(days[2].deskFor(PaymentMethod.upi), 300);
      expect(days[2].deskFor(PaymentMethod.card), 0);
      expect(days[2].net, 850);
      expect(days[3].deskFor(PaymentMethod.cash), 7540);
    });

    test('the totals row adds every column', () {
      final total = collectionsTotal(collectionsByDay(rows));

      expect(total.day, isNull);
      expect(total.online, 5000);
      expect(total.deskFor(PaymentMethod.cash), 8090);
      expect(total.deskFor(PaymentMethod.upi), 300);
      expect(total.deskFor(PaymentMethod.card), 0);
      expect(total.refunds, -1500);
      expect(total.net, 11890);
    });

    test('no rows give no days and a zero total', () {
      expect(collectionsByDay(const []), isEmpty);
      expect(collectionsTotal(const []).net, 0);
    });
  });

  group('ledgerByDay', () {
    final rows = [
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.room,
          gross: 10000,
          discount: 1000,
          tax: 1080),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.ancillary,
          source: 'cleaning_fee',
          gross: 500,
          tax: 60),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.foodBeverage,
          source: 'walk_in',
          gross: 550),
      ledgerRow(
          day: DateTime(2026, 8, 5),
          category: LedgerCategory.ancillary,
          source: 'cancellation_fee',
          gross: 500),
    ];

    test('category columns hold taxable amounts; taxable + tax = total', () {
      final days = ledgerByDay(rows);

      expect(days.map((d) => d.day), [DateTime(2026, 8, 5), DateTime(2026, 8, 10)]);
      final aug10 = days[1];
      expect(aug10.categoryTotal(LedgerCategory.room), 9000);
      expect(aug10.categoryTotal(LedgerCategory.ancillary), 500);
      expect(aug10.categoryTotal(LedgerCategory.foodBeverage), 550);
      expect(aug10.categoryTotal(LedgerCategory.spaActivities), 0);
      expect(aug10.taxable, 10050);
      expect(aug10.tax, 1140);
      expect(aug10.total, 11190);
    });

    test('the totals row adds every day', () {
      final total = ledgerTotal(ledgerByDay(rows));

      expect(total.day, isNull);
      expect(total.categoryTotal(LedgerCategory.ancillary), 1000);
      expect(total.taxable, 10550);
      expect(total.tax, 1140);
      expect(total.total, 11690);
    });

    test("tax is kept per category and adds up to the day's tax", () {
      final days = ledgerByDay([
        ledgerRow(day: DateTime(2026, 8, 10), category: LedgerCategory.room, gross: 2000, tax: 240),
        ledgerRow(
            day: DateTime(2026, 8, 10),
            category: LedgerCategory.foodBeverage,
            source: 'in_stay_order',
            gross: 500,
            tax: 25),
        ledgerRow(
            day: DateTime(2026, 8, 10),
            category: LedgerCategory.foodBeverage,
            source: 'walk_in',
            gross: 300,
            tax: 36),
        ledgerRow(
            day: DateTime(2026, 8, 11),
            category: LedgerCategory.spaActivities,
            source: 'activity_booking',
            gross: 2000,
            tax: 360),
      ]);

      expect(days[0].taxFor(LedgerCategory.room), 240);
      expect(days[0].taxFor(LedgerCategory.foodBeverage), 61);
      expect(days[0].taxFor(LedgerCategory.spaActivities), 0);
      expect(days[0].tax, 301);
      expect(days[0].total, 2800 + 301);
      final total = ledgerTotal(days);
      expect(total.taxFor(LedgerCategory.spaActivities), 360);
      expect(total.taxFor(LedgerCategory.foodBeverage), 61);
      expect(total.tax, 661);
    });
  });

  test('formatMoney keeps paise and Indian grouping', () {
    expect(formatMoney(1080), '₹1,080.00');
    expect(formatMoney(120000), '₹1,20,000.00');
    expect(formatMoney(36.5), '₹36.50');
  });

  test('isoDate is yyyy-MM-dd', () {
    expect(isoDate(DateTime(2026, 8, 1)), '2026-08-01');
  });
}

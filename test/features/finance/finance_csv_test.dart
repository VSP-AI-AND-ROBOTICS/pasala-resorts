import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_csv.dart';
import 'package:pasala/features/reports/csv_export.dart';

import '../../support/fake_finance_source.dart';

void main() {
  final resort = financeResort();
  final from = DateTime(2026, 8, 1);
  final to = DateTime(2026, 8, 31);

  test('every file opens with the resort, its GSTIN and the period', () {
    expect(financeCsvHeader(resort, from, to), [
      ['Resort R', 'GSTIN 29ABCDE1234F1Z5'],
      ['Period', '2026-08-01', '2026-08-31'],
    ]);
  });

  test('a resort without a GSTIN says so', () {
    expect(gstinLabel(financeResort(gstin: null)), 'GSTIN not set');
    expect(gstinLabel(financeResort(gstin: '   ')), 'GSTIN not set');
  });

  test('collections keep channel, source and method per line', () {
    final rows = collectionsCsv(resort, from, to, [
      collectionRow(
          day: DateTime(2026, 8, 5),
          source: CollectionSource.refund,
          amount: -1500),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.bankTransfer,
          txnCount: 2,
          amount: 550),
    ]);

    expect(rows.take(2), financeCsvHeader(resort, from, to));
    expect(rows[2], ['Date', 'Channel', 'Source', 'Method', 'Transactions', 'Amount']);
    expect(rows[3], ['2026-08-05', 'online', 'refund', 'gateway', '1', '-1500.00']);
    expect(rows[4], ['2026-08-10', 'front_desk', 'walk_in_sale', 'bank_transfer', '2', '550.00']);
  });

  test('ledger lines carry category, source and every amount', () {
    final rows = ledgerCsv(resort, from, to, [
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.room,
          gross: 10000,
          discount: 1000,
          tax: 1080),
    ]);

    expect(rows[2],
        ['Date', 'Category', 'Source', 'Gross', 'Discount', 'Taxable', 'Tax', 'Net']);
    expect(rows[3],
        ['2026-08-10', 'room', 'booking', '10000.00', '1000.00', '9000.00', '1080.00', '10080.00']);
  });

  test('settlement lines carry the whole bill and how it was paid', () {
    final rows = settlementsCsv(resort, from, to, [
      settlementRow(
        room: 9000,
        cleaningFee: 500,
        taxPct: 12,
        tax: 1140,
        food: 700,
        activities: 1200,
        advancePaid: 5000,
        balanceDesk: 7540,
        deskMethod: PaymentMethod.cash,
        deskReference: 'R-101',
        recordedByName: 'Sita Staff',
      ),
      settlementRow(reservationId: 'r2', room: 3000, balanceOnline: 2000, advancePaid: 1000),
    ]);

    expect(rows[2], [
      'Reservation', 'Guest', 'Unit', 'Arrival', 'Departure', 'Room', 'Cleaning fee',
      'Tax %', 'Tax', 'Food', 'Activities', 'Total', 'Advance paid', 'Balance online',
      'Balance desk', 'Desk method', 'Desk reference', 'Recorded by', 'Outstanding',
    ]);
    expect(rows[3], [
      'r1', 'Gita Guest', 'Cottage 1', '2026-08-10', '2026-08-12', '9000.00', '500.00',
      '12', '1140.00', '700.00', '1200.00', '12540.00', '5000.00', '0.00',
      '7540.00', 'cash', 'R-101', 'Sita Staff', '0.00',
    ]);
    expect(rows[4].sublist(15, 18), ['', '', '']);
  });

  test("today's file lists every figure for the resort's today", () {
    final rows = todayCsv(financeSummary(
      online: 1000,
      desk: {PaymentMethod.cash: 2800, PaymentMethod.card: 120},
      refunds: 600,
      roomTax: 240,
      inHouseCount: 1,
      inHouseBalance: 1200,
    ));

    expect(rows[1], ['Period', '2026-09-25', '2026-09-25']);
    expect(rows.skip(2).toList(), [
      ['Figure', 'Amount'],
      ['Online collected', '1000.00'],
      ['Desk collected', '2920.00'],
      ['Desk: Cash', '2800.00'],
      ['Desk: Card', '120.00'],
      ['Desk: UPI', '0.00'],
      ['Desk: Bank transfer', '0.00'],
      ['Desk: Other', '0.00'],
      ['Refunds', '600.00'],
      ['Net collected', '3320.00'],
      ['Room tax', '240.00'],
      ['In-house guests', '1'],
      ['In-house unpaid balance', '1200.00'],
    ]);
  });

  test('the file name is <slug>-<report>-<from>-<to>.csv', () {
    expect(
        financeCsvFileName('pasala', 'collections', DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
        'pasala-collections-2026-09-01-2026-09-30.csv');
  });

  test('a resort name with a comma is quoted in the file', () {
    final csv = toCsv(financeCsvHeader(financeResort(name: 'Pasala, Riverside'), from, to));

    expect(csv, startsWith('"Pasala, Riverside",GSTIN 29ABCDE1234F1Z5\r\n'));
  });
}

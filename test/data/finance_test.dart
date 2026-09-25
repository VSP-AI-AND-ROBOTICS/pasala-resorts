import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';

void main() {
  test('CollectionRow.fromJson parses a report_collections row', () {
    final row = CollectionRow.fromJson(const {
      'day': '2026-08-10',
      'channel': 'front_desk',
      'source': 'walk_in_sale',
      'method': 'upi',
      'txn_count': 2,
      'amount': 550.5,
    });

    expect(row.day, DateTime(2026, 8, 10));
    expect(row.channel, CollectionChannel.frontDesk);
    expect(row.source, CollectionSource.walkInSale);
    expect(row.method, PaymentMethod.upi);
    expect(row.txnCount, 2);
    expect(row.amount, 550.5);
  });

  test('a refund line keeps its negative amount', () {
    final row = CollectionRow.fromJson(const {
      'day': '2026-08-05',
      'channel': 'online',
      'source': 'refund',
      'method': 'gateway',
      'txn_count': 1,
      'amount': -1500,
    });

    expect(row.source, CollectionSource.refund);
    expect(row.amount, -1500);
  });

  test('an unknown channel, source or category is rejected, not defaulted', () {
    expect(() => CollectionChannel.fromWire('pigeon'), throwsArgumentError);
    expect(() => CollectionSource.fromWire('lottery'), throwsArgumentError);
    expect(() => LedgerCategory.fromWire('casino'), throwsArgumentError);
  });

  test('LedgerRow.fromJson parses a report_ledger row', () {
    final row = LedgerRow.fromJson(const {
      'day': '2026-08-10',
      'category': 'room',
      'source': 'booking',
      'gross': 10000,
      'discount': 1000,
      'taxable': 9000,
      'tax': 1080,
      'net': 10080,
    });

    expect(row.day, DateTime(2026, 8, 10));
    expect(row.category, LedgerCategory.room);
    expect(row.source, 'booking');
    expect(
      [row.gross, row.discount, row.taxable, row.tax, row.net],
      [10000, 1000, 9000, 1080, 10080],
    );
  });

  test('ledger categories have their own labels', () {
    expect(LedgerCategory.values.map((c) => c.label).toList(), [
      'Room',
      'F&B',
      'Spa/Activities',
      'Ancillary',
    ]);
  });

  test('SettlementRow.fromJson parses a desk settlement', () {
    final row = SettlementRow.fromJson(const {
      'reservation_id': 'r1',
      'guest_name': 'Gita Guest',
      'unit_name': 'Cottage 1',
      'arrival': '2026-08-10',
      'departure': '2026-08-12',
      'room': 9000,
      'cleaning_fee': 500,
      'tax_pct': 12,
      'tax': 1140,
      'food': 700,
      'activities': 1200,
      'total': 12540,
      'advance_paid': 5000,
      'balance_online': 0,
      'balance_desk': 7540,
      'desk_method': 'cash',
      'desk_reference': 'R-101',
      'recorded_by_name': 'Sita Staff',
      'outstanding': 0,
    });

    expect(row.reservationId, 'r1');
    expect(row.guestName, 'Gita Guest');
    expect(row.unitName, 'Cottage 1');
    expect(row.arrival, DateTime(2026, 8, 10));
    expect(row.departure, DateTime(2026, 8, 12));
    expect(row.total, 12540);
    expect(row.balanceDesk, 7540);
    expect(row.deskMethod, PaymentMethod.cash);
    expect(row.deskReference, 'R-101');
    expect(row.recordedByName, 'Sita Staff');
    expect(row.outstanding, 0);
  });

  test('an online settlement has no desk method', () {
    final row = SettlementRow.fromJson(const {
      'reservation_id': 'r2',
      'guest_name': 'Ravi Guest',
      'unit_name': 'Cottage 2',
      'arrival': '2026-08-20',
      'departure': '2026-08-21',
      'room': 3000,
      'cleaning_fee': 0,
      'tax_pct': 0,
      'tax': 0,
      'food': 0,
      'activities': 0,
      'total': 3000,
      'advance_paid': 1000,
      'balance_online': 2000,
      'balance_desk': 0,
      'desk_method': null,
      'desk_reference': null,
      'recorded_by_name': null,
      'outstanding': 0,
    });

    expect(row.deskMethod, isNull);
    expect(row.deskReference, isNull);
    expect(row.recordedByName, isNull);
    expect(row.balanceOnline, 2000);
  });

  test('FinanceSummary.fromJson parses finance_summary', () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort R',
        'slug': 'fin-r',
        'gstin': '29ABCDE1234F1Z5',
        'tax_pct': 12,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
      'online_collected': 1000,
      'desk_collected': {
        'total': 2920,
        'cash': 2800,
        'card': 120,
        'upi': 0,
        'bank_transfer': 0,
        'other': 0,
      },
      'refunds': 600,
      'net_collected': 3320,
      'room_tax': 240,
      'in_house_count': 1,
      'in_house_balance': 1200,
    });

    expect(s.resort.name, 'Resort R');
    expect(s.resort.slug, 'fin-r');
    expect(s.resort.gstin, '29ABCDE1234F1Z5');
    expect(s.resort.taxPct, 12);
    expect(s.resort.timezone, 'Asia/Kolkata');
    expect(s.resort.today, DateTime(2026, 9, 25));
    expect(s.onlineCollected, 1000);
    expect(s.deskCollected, 2920);
    expect(s.deskByMethod[PaymentMethod.cash], 2800);
    expect(s.deskByMethod[PaymentMethod.card], 120);
    expect(s.deskByMethod.keys, PaymentMethod.desk);
    expect(s.refunds, 600);
    expect(s.netCollected, 3320);
    expect(s.roomTax, 240);
    expect(s.inHouseCount, 1);
    expect(s.inHouseBalance, 1200);
  });

  test('a resort with no GSTIN and missing figures parse as null and zero', () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort S',
        'slug': 'fin-s',
        'gstin': null,
        'tax_pct': 0,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
    });

    expect(s.resort.gstin, isNull);
    expect(s.onlineCollected, 0);
    expect(s.deskCollected, 0);
    expect(s.deskByMethod.values, everyElement(0));
    expect(s.inHouseCount, 0);
  });

  test("reads the food and spa rates and today's food and spa tax", () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort T',
        'slug': 'tax-t',
        'gstin': null,
        'tax_pct': 12,
        'fnb_tax_pct': 12,
        'spa_tax_pct': 18,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
      'room_tax': 240,
      'food_tax': 72.25,
      'spa_tax': 468,
    });

    expect(s.resort.fnbTaxPct, 12);
    expect(s.resort.spaTaxPct, 18);
    expect(s.roomTax, 240);
    expect(s.foodTax, 72.25);
    expect(s.spaTax, 468);
  });

  test('a summary without the food and spa keys reads them as 0', () {
    final s = FinanceSummary.fromJson(const {
      'resort': {
        'name': 'Resort S',
        'slug': 'fin-s',
        'gstin': null,
        'tax_pct': 0,
        'timezone': 'Asia/Kolkata',
        'today': '2026-09-25',
      },
    });

    expect(s.resort.fnbTaxPct, 0);
    expect(s.resort.spaTaxPct, 0);
    expect(s.foodTax, 0);
    expect(s.spaTax, 0);
  });
}

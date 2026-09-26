import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_pdf.dart';
import 'package:pasala/features/finance/finance_tables.dart';

import '../../support/fake_finance_source.dart';

final _from = DateTime(2026, 8, 1);
final _to = DateTime(2026, 8, 31);
String m(num v) => formatMoney(v);

void main() {
  final resort = financeResort();

  test('file names follow the CSV names with .pdf', () {
    expect(
      financePdfFileName('fin-r', 'ledger', _from, _to),
      'fin-r-ledger-2026-08-01-2026-08-31.pdf',
    );
  });

  group('Collections', () {
    final rows = [
      collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
      collectionRow(
        day: DateTime(2026, 8, 5),
        source: CollectionSource.refund,
        amount: -1500,
      ),
      collectionRow(
        day: DateTime(2026, 8, 10),
        channel: CollectionChannel.frontDesk,
        source: CollectionSource.walkInSale,
        method: PaymentMethod.cash,
        amount: 550,
      ),
      collectionRow(
        day: DateTime(2026, 8, 10),
        channel: CollectionChannel.frontDesk,
        source: CollectionSource.walkInSale,
        method: PaymentMethod.upi,
        amount: 300,
      ),
      collectionRow(
        day: DateTime(2026, 8, 12),
        channel: CollectionChannel.frontDesk,
        source: CollectionSource.checkoutBalance,
        method: PaymentMethod.cash,
        amount: 7540,
      ),
    ];

    test('one row per day, online and each desk method, refunds and net', () {
      final pdf = collectionsPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Collections');
      expect(pdf.resortName, 'Resort R');
      expect(pdf.gstinLabel, 'GSTIN 29ABCDE1234F1Z5');
      expect(pdf.periodLabel, '1 Aug 2026 – 31 Aug 2026');
      expect(pdf.fileName, 'fin-r-collections-2026-08-01-2026-08-31.pdf');
      expect(pdf.columns.map((c) => c.header), [
        'Date',
        'Online',
        'Cash',
        'Card',
        'UPI',
        'Bank',
        'Other',
        'Refunds',
        'Net',
      ]);
      expect(pdf.rows, [
        ['1 Aug 2026', m(5000), m(0), m(0), m(0), m(0), m(0), m(0), m(5000)],
        ['5 Aug 2026', m(0), m(0), m(0), m(0), m(0), m(0), m(-1500), m(-1500)],
        ['10 Aug 2026', m(0), m(550), m(0), m(300), m(0), m(0), m(0), m(850)],
        ['12 Aug 2026', m(0), m(7540), m(0), m(0), m(0), m(0), m(0), m(7540)],
      ]);
      expect(pdf.totals, [
        'Total',
        m(5000),
        m(8090),
        m(0),
        m(300),
        m(0),
        m(0),
        m(-1500),
        m(11890),
      ]);
    });

    test('an empty period has no totals and says so', () {
      final pdf = collectionsPdf(resort, _from, _to, const []);
      expect(pdf.rows, isEmpty);
      expect(pdf.totals, isNull);
      expect(pdf.emptyMessage, 'No collections in this period.');
    });
  });

  group('Ledger', () {
    final rows = [
      ledgerRow(
        day: DateTime(2026, 8, 10),
        gross: 10000,
        discount: 1000,
        tax: 1080,
      ),
      ledgerRow(
        day: DateTime(2026, 8, 10),
        category: LedgerCategory.ancillary,
        source: 'cleaning_fee',
        gross: 500,
        tax: 60,
      ),
      ledgerRow(
        day: DateTime(2026, 8, 10),
        category: LedgerCategory.ancillary,
        source: 'cancellation_fee',
        gross: 2000,
      ),
      ledgerRow(
        day: DateTime(2026, 8, 11),
        category: LedgerCategory.foodBeverage,
        source: 'in_stay_order',
        gross: 840,
        tax: 40,
      ),
      ledgerRow(
        day: DateTime(2026, 8, 11),
        category: LedgerCategory.spaActivities,
        source: 'activity_booking',
        gross: 1180,
        tax: 180,
      ),
    ];

    test('one row per day and category, sources summed, in category order', () {
      final pdf = ledgerPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Ledger');
      expect(pdf.columns.map((c) => c.header), [
        'Date',
        'Category',
        'Gross',
        'Discount',
        'Taxable',
        'Tax',
        'Net',
      ]);
      expect(pdf.rows, [
        ['10 Aug 2026', 'Room', m(10000), m(1000), m(9000), m(1080), m(10080)],
        ['10 Aug 2026', 'Ancillary', m(2500), m(0), m(2500), m(60), m(2560)],
        ['11 Aug 2026', 'F&B', m(840), m(0), m(840), m(40), m(880)],
        [
          '11 Aug 2026',
          'Spa/Activities',
          m(1180),
          m(0),
          m(1180),
          m(180),
          m(1360),
        ],
      ]);
      expect(pdf.totals, [
        'Total',
        '',
        m(14520),
        m(1000),
        m(13520),
        m(1360),
        m(14880),
      ]);
    });

    test('notes give taxable and tax per category over the period', () {
      expect(ledgerPdf(resort, _from, _to, rows).notes, [
        'Tax by category',
        'Room: taxable ${m(9000)}, tax ${m(1080)}',
        'F&B: taxable ${m(840)}, tax ${m(40)}',
        'Spa/Activities: taxable ${m(1180)}, tax ${m(180)}',
        'Ancillary: taxable ${m(2500)}, tax ${m(60)}',
      ]);
    });

    test('an empty period says so', () {
      final pdf = ledgerPdf(resort, _from, _to, const []);
      expect(pdf.totals, isNull);
      expect(pdf.notes, isEmpty);
      expect(pdf.emptyMessage, 'No revenue in this period.');
    });
  });

  group('Settlements', () {
    final rows = [
      settlementRow(
        reservationId: 'r1',
        room: 9000,
        cleaningFee: 500,
        taxPct: 12,
        tax: 1140,
        food: 840,
        activities: 1180,
        advancePaid: 3192,
        balanceDesk: 9468,
        deskMethod: PaymentMethod.cash,
        deskReference: 'R-17',
      ),
      settlementRow(
        reservationId: 'r2',
        guestName: 'Ravi Rao',
        unitName: 'Lake Villa',
        room: 5000,
        advancePaid: 2000,
        balanceOnline: 3000,
      ),
      settlementRow(
        reservationId: 'r3',
        guestName: 'Owes Money',
        room: 1000,
        outstanding: 1000,
      ),
    ];

    test('one condensed row per checkout, and a totals row', () {
      final pdf = settlementsPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Settlements');
      expect(pdf.columns.map((c) => c.header), [
        'Guest',
        'Unit',
        'Stay',
        'Room',
        'Cleaning',
        'Tax',
        'Food',
        'Activities',
        'Total',
        'Advance',
        'Balance',
        'Paid by',
        'Outstanding',
      ]);
      expect(pdf.rows, [
        [
          'Gita Guest',
          'Cottage 1',
          '10 Aug 2026 – 12 Aug 2026',
          m(9000),
          m(500),
          '${m(1140)} (12%)',
          m(840),
          m(1180),
          m(12660),
          m(3192),
          m(9468),
          'Cash · R-17',
          m(0),
        ],
        [
          'Ravi Rao',
          'Lake Villa',
          '10 Aug 2026 – 12 Aug 2026',
          m(5000),
          m(0),
          m(0),
          m(0),
          m(0),
          m(5000),
          m(2000),
          m(3000),
          'Online',
          m(0),
        ],
        [
          'Owes Money',
          'Cottage 1',
          '10 Aug 2026 – 12 Aug 2026',
          m(1000),
          m(0),
          m(0),
          m(0),
          m(0),
          m(1000),
          m(0),
          m(0),
          '—',
          m(1000),
        ],
      ]);
      expect(pdf.totals, [
        'Total',
        '',
        '',
        m(15000),
        m(500),
        m(1140),
        m(840),
        m(1180),
        m(18660),
        m(5192),
        m(12468),
        '',
        m(1000),
      ]);
    });

    test('an empty period says so', () {
      final pdf = settlementsPdf(resort, _from, _to, const []);
      expect(pdf.totals, isNull);
      expect(pdf.emptyMessage, 'No checkouts in this period.');
    });

    test('every row fits the columns', () {
      final pdf = settlementsPdf(resort, _from, _to, rows);
      for (final row in [...pdf.rows, pdf.totals!]) {
        expect(row, hasLength(pdf.columns.length));
      }
    });
  });

  test('a resort without GSTIN says so', () {
    expect(
      collectionsPdf(
        financeResort(gstin: null),
        _from,
        _to,
        const [],
      ).gstinLabel,
      'GSTIN not set',
    );
  });
}

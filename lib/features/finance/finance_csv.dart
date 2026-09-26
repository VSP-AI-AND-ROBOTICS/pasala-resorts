import '../../core/format.dart';
import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';
import 'finance_tables.dart';

/// Plain two-decimal amounts for spreadsheets: `1080.00`, `-1500.00`.
String csvMoney(num amount) => amount.toStringAsFixed(2);

/// `GSTIN 29ABCDE1234F1Z5`, or `GSTIN not set` for a resort without one.
String gstinLabel(FinanceResort resort) {
  final gstin = resort.gstin?.trim() ?? '';
  return gstin.isEmpty ? 'GSTIN not set' : 'GSTIN $gstin';
}

/// The two lines every finance file starts with: resort and GSTIN, then
/// the period.
List<List<String>> financeCsvHeader(
        FinanceResort resort, DateTime from, DateTime to) =>
    [
      [resort.name, gstinLabel(resort)],
      ['Period', isoDate(from), isoDate(to)],
    ];

/// `<slug>-<report>-<from>-<to>.csv`, e.g.
/// `pasala-collections-2026-09-01-2026-09-30.csv`.
String financeCsvFileName(
        String slug, String report, DateTime from, DateTime to) =>
    '$slug-$report-${isoDate(from)}-${isoDate(to)}.csv';

List<List<String>> todayCsv(FinanceSummary s) => [
      ...financeCsvHeader(s.resort, s.resort.today, s.resort.today),
      ['Figure', 'Amount'],
      ['Online collected', csvMoney(s.onlineCollected)],
      ['Desk collected', csvMoney(s.deskCollected)],
      for (final m in PaymentMethod.desk)
        ['Desk: ${m.label}', csvMoney(s.deskByMethod[m] ?? 0)],
      ['Refunds', csvMoney(s.refunds)],
      ['Net collected', csvMoney(s.netCollected)],
      ['Room tax', csvMoney(s.roomTax)],
      ['F&B tax', csvMoney(s.foodTax)],
      ['Spa tax', csvMoney(s.spaTax)],
      ['In-house guests', '${s.inHouseCount}'],
      ['In-house unpaid balance', csvMoney(s.inHouseBalance)],
    ];

List<List<String>> collectionsCsv(FinanceResort resort, DateTime from,
        DateTime to, List<CollectionRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      ['Date', 'Channel', 'Source', 'Method', 'Transactions', 'Amount'],
      for (final r in rows)
        [
          isoDate(r.day),
          r.channel.wire,
          r.source.wire,
          r.method.wire,
          '${r.txnCount}',
          csvMoney(r.amount),
        ],
    ];

List<List<String>> ledgerCsv(FinanceResort resort, DateTime from, DateTime to,
        List<LedgerRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      ['Date', 'Category', 'Source', 'Gross', 'Discount', 'Taxable', 'Tax', 'Net'],
      for (final r in rows)
        [
          isoDate(r.day),
          r.category.wire,
          r.source,
          csvMoney(r.gross),
          csvMoney(r.discount),
          csvMoney(r.taxable),
          csvMoney(r.tax),
          csvMoney(r.net),
        ],
    ];

List<List<String>> settlementsCsv(FinanceResort resort, DateTime from,
        DateTime to, List<SettlementRow> rows) =>
    [
      ...financeCsvHeader(resort, from, to),
      [
        'Reservation', 'Guest', 'Unit', 'Arrival', 'Departure', 'Room',
        'Cleaning fee', 'Tax %', 'Tax', 'Food', 'Activities', 'Total',
        'Advance paid', 'Balance online', 'Balance desk', 'Desk method',
        'Desk reference', 'Recorded by', 'Outstanding',
      ],
      for (final r in rows)
        [
          r.reservationId,
          r.guestName,
          r.unitName,
          isoDate(r.arrival),
          isoDate(r.departure),
          csvMoney(r.room),
          csvMoney(r.cleaningFee),
          formatPct(r.taxPct),
          csvMoney(r.tax),
          csvMoney(r.food),
          csvMoney(r.activities),
          csvMoney(r.total),
          csvMoney(r.advancePaid),
          csvMoney(r.balanceOnline),
          csvMoney(r.balanceDesk),
          r.deskMethod?.wire ?? '',
          r.deskReference ?? '',
          r.recordedByName ?? '',
          csvMoney(r.outstanding),
        ],
    ];

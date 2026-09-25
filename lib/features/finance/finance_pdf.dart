import '../../core/format.dart';
import '../../core/pdf/report_pdf.dart';
import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';
import 'finance_csv.dart' show gstinLabel;
import 'finance_tables.dart';

/// `<slug>-<report>-<from>-<to>.pdf`: the CSV's name with `.pdf`.
String financePdfFileName(
  String slug,
  String report,
  DateTime from,
  DateTime to,
) => '$slug-$report-${isoDate(from)}-${isoDate(to)}.pdf';

String _period(DateTime from, DateTime to) =>
    '${formatDate(from)} – ${formatDate(to)}';

num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);

/// Collections as on screen: one row per day, online and each desk method,
/// refunds (negative) and the day's net; a totals row.
ReportPdf collectionsPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<CollectionRow> rows,
) {
  final days = collectionsByDay(rows);
  List<String> cells(CollectionDay d) => [
    d.day == null ? 'Total' : formatDate(d.day!),
    formatMoney(d.online),
    for (final m in PaymentMethod.desk) formatMoney(d.deskFor(m)),
    formatMoney(d.refunds),
    formatMoney(d.net),
  ];
  return ReportPdf(
    title: 'Collections',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'collections', from, to),
    columns: [
      const ReportPdfColumn('Date', flex: 1.4),
      const ReportPdfColumn('Online', numeric: true),
      for (final m in PaymentMethod.desk)
        ReportPdfColumn(
          m == PaymentMethod.bankTransfer ? 'Bank' : m.label,
          numeric: true,
        ),
      const ReportPdfColumn('Refunds', numeric: true),
      const ReportPdfColumn('Net', numeric: true),
    ],
    rows: [for (final d in days) cells(d)],
    totals: days.isEmpty ? null : cells(collectionsTotal(days)),
    emptyMessage: 'No collections in this period.',
  );
}

/// Running sums of ledger lines.
class _LedgerSum {
  num gross = 0, discount = 0, taxable = 0, tax = 0, net = 0;

  void add(LedgerRow r) {
    gross += r.gross;
    discount += r.discount;
    taxable += r.taxable;
    tax += r.tax;
    net += r.net;
  }

  List<String> get money => [
    formatMoney(gross),
    formatMoney(discount),
    formatMoney(taxable),
    formatMoney(tax),
    formatMoney(net),
  ];
}

/// Ledger with tax per category: one row per day and category (the
/// sources of a category summed), a totals row, and a "Tax by category"
/// note block over the whole period.
ReportPdf ledgerPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<LedgerRow> rows,
) {
  final byDayCategory = <(DateTime, LedgerCategory), _LedgerSum>{};
  final byCategory = <LedgerCategory, _LedgerSum>{};
  final total = _LedgerSum();
  for (final r in rows) {
    byDayCategory.putIfAbsent((r.day, r.category), _LedgerSum.new).add(r);
    byCategory.putIfAbsent(r.category, _LedgerSum.new).add(r);
    total.add(r);
  }
  final keys = byDayCategory.keys.toList()
    ..sort((a, b) {
      final byDay = a.$1.compareTo(b.$1);
      return byDay != 0 ? byDay : a.$2.index.compareTo(b.$2.index);
    });
  return ReportPdf(
    title: 'Ledger',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'ledger', from, to),
    columns: const [
      ReportPdfColumn('Date', flex: 1.4),
      ReportPdfColumn('Category', flex: 1.4),
      ReportPdfColumn('Gross', numeric: true),
      ReportPdfColumn('Discount', numeric: true),
      ReportPdfColumn('Taxable', numeric: true),
      ReportPdfColumn('Tax', numeric: true),
      ReportPdfColumn('Net', numeric: true),
    ],
    rows: [
      for (final k in keys)
        [formatDate(k.$1), k.$2.label, ...byDayCategory[k]!.money],
    ],
    totals: rows.isEmpty ? null : ['Total', '', ...total.money],
    notes: rows.isEmpty
        ? const []
        : [
            'Tax by category',
            for (final c in LedgerCategory.values)
              if (byCategory[c] != null)
                '${c.label}: taxable ${formatMoney(byCategory[c]!.taxable)}, '
                    'tax ${formatMoney(byCategory[c]!.tax)}',
          ],
    emptyMessage: 'No revenue in this period.',
  );
}

/// `Cash · R-17`, `Online`, both joined with ` + `, or `—`.
String _paidBy(SettlementRow r) {
  final desk = [
    r.deskMethod?.label,
    r.deskReference,
  ].whereType<String>().join(' · ');
  final parts = [if (r.balanceOnline != 0) 'Online', if (desk.isNotEmpty) desk];
  return parts.isEmpty ? '—' : parts.join(' + ');
}

/// Settlements, condensed to fit A4 landscape: the whole bill, advance,
/// balance (online + desk), how the balance was paid, and outstanding.
ReportPdf settlementsPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<SettlementRow> rows,
) {
  String money(num Function(SettlementRow) pick) =>
      formatMoney(_sum(rows.map(pick)));
  return ReportPdf(
    title: 'Settlements',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'settlements', from, to),
    columns: const [
      ReportPdfColumn('Guest', flex: 1.6),
      ReportPdfColumn('Unit', flex: 1.2),
      ReportPdfColumn('Stay', flex: 1.8),
      ReportPdfColumn('Room', numeric: true),
      ReportPdfColumn('Cleaning', numeric: true),
      ReportPdfColumn('Tax', numeric: true, flex: 1.3),
      ReportPdfColumn('Food', numeric: true),
      ReportPdfColumn('Activities', numeric: true),
      ReportPdfColumn('Total', numeric: true),
      ReportPdfColumn('Advance', numeric: true),
      ReportPdfColumn('Balance', numeric: true),
      ReportPdfColumn('Paid by', flex: 1.4),
      ReportPdfColumn('Outstanding', numeric: true),
    ],
    rows: [
      for (final r in rows)
        [
          r.guestName,
          r.unitName,
          '${formatDate(r.arrival)} – ${formatDate(r.departure)}',
          formatMoney(r.room),
          formatMoney(r.cleaningFee),
          r.taxPct == 0
              ? formatMoney(r.tax)
              : '${formatMoney(r.tax)} (${formatPct(r.taxPct)}%)',
          formatMoney(r.food),
          formatMoney(r.activities),
          formatMoney(r.total),
          formatMoney(r.advancePaid),
          formatMoney(r.balanceOnline + r.balanceDesk),
          _paidBy(r),
          formatMoney(r.outstanding),
        ],
    ],
    totals: rows.isEmpty
        ? null
        : [
            'Total',
            '',
            '',
            money((r) => r.room),
            money((r) => r.cleaningFee),
            money((r) => r.tax),
            money((r) => r.food),
            money((r) => r.activities),
            money((r) => r.total),
            money((r) => r.advancePaid),
            money((r) => r.balanceOnline + r.balanceDesk),
            '',
            money((r) => r.outstanding),
          ],
    emptyMessage: 'No checkouts in this period.',
  );
}

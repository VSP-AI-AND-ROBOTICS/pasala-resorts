import 'package:intl/intl.dart';

import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';

final _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Finance figures keep their paise (`1080` -> `₹1,080.00`), unlike
/// `formatInr`, which rounds to whole rupees for guests.
String formatMoney(num amount) => _money.format(amount);

/// `yyyy-MM-dd`: the date format of every finance CSV and file name.
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);

/// One day of the Collections view: online money, desk money by method,
/// and refunds (zero or negative). [day] is null on the totals row.
class CollectionDay {
  const CollectionDay({
    this.day,
    this.online = 0,
    this.desk = const {},
    this.refunds = 0,
  });

  final DateTime? day;

  /// Online money that is not a refund.
  final num online;
  final Map<PaymentMethod, num> desk;
  final num refunds;

  num deskFor(PaymentMethod method) => desk[method] ?? 0;
  num get net => online + _sum(desk.values) + refunds;
}

/// Pivots `report_collections` lines into one [CollectionDay] per day,
/// oldest first.
List<CollectionDay> collectionsByDay(List<CollectionRow> rows) {
  final days = <DateTime>{};
  final online = <DateTime, num>{};
  final refunds = <DateTime, num>{};
  final desk = <DateTime, Map<PaymentMethod, num>>{};
  for (final r in rows) {
    days.add(r.day);
    if (r.source == CollectionSource.refund) {
      refunds[r.day] = (refunds[r.day] ?? 0) + r.amount;
    } else if (r.channel == CollectionChannel.online) {
      online[r.day] = (online[r.day] ?? 0) + r.amount;
    } else {
      final byMethod = desk.putIfAbsent(r.day, () => {});
      byMethod[r.method] = (byMethod[r.method] ?? 0) + r.amount;
    }
  }
  return [
    for (final d in days.toList()..sort())
      CollectionDay(
        day: d,
        online: online[d] ?? 0,
        desk: desk[d] ?? const {},
        refunds: refunds[d] ?? 0,
      ),
  ];
}

/// The totals row of [days].
CollectionDay collectionsTotal(List<CollectionDay> days) => CollectionDay(
      online: _sum(days.map((d) => d.online)),
      desk: {
        for (final m in PaymentMethod.desk) m: _sum(days.map((d) => d.deskFor(m))),
      },
      refunds: _sum(days.map((d) => d.refunds)),
    );

/// One day of the Ledger view: each category's taxable amount, and the
/// day's tax. [day] is null on the totals row.
class LedgerDay {
  const LedgerDay({this.day, this.byCategory = const {}, this.tax = 0});

  final DateTime? day;
  final Map<LedgerCategory, num> byCategory;
  final num tax;

  num categoryTotal(LedgerCategory category) => byCategory[category] ?? 0;
  num get taxable => _sum(byCategory.values);
  num get total => taxable + tax;
}

/// Pivots `report_ledger` lines into one [LedgerDay] per day, oldest first.
List<LedgerDay> ledgerByDay(List<LedgerRow> rows) {
  final byDay = <DateTime, Map<LedgerCategory, num>>{};
  final tax = <DateTime, num>{};
  for (final r in rows) {
    final categories = byDay.putIfAbsent(r.day, () => {});
    categories[r.category] = (categories[r.category] ?? 0) + r.taxable;
    tax[r.day] = (tax[r.day] ?? 0) + r.tax;
  }
  return [
    for (final d in byDay.keys.toList()..sort())
      LedgerDay(day: d, byCategory: byDay[d]!, tax: tax[d] ?? 0),
  ];
}

/// The totals row of [days].
LedgerDay ledgerTotal(List<LedgerDay> days) => LedgerDay(
      byCategory: {
        for (final c in LedgerCategory.values)
          c: _sum(days.map((d) => d.categoryTotal(c))),
      },
      tax: _sum(days.map((d) => d.tax)),
    );

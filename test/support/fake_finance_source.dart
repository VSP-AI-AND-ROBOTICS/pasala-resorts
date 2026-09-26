import 'dart:async';

import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/reports/providers.dart' show ReportFilter;

/// In-memory [FinanceSource]. Set the `...Value`/`...Rows` fields for what
/// the server would return, an `...Error` to make that call throw, [hold]
/// to keep every call loading, and read the call logs to assert what a
/// screen asked for.
class FakeFinanceSource implements FinanceSource {
  FinanceSummary summaryValue = financeSummary();
  List<CollectionRow> collectionRows = [];
  List<LedgerRow> ledgerRows = [];
  List<SettlementRow> settlementRows = [];
  Object? summaryError;
  Object? collectionsError;
  Object? ledgerError;
  Object? settlementsError;

  /// When set, every call waits for it to complete.
  Completer<void>? hold;

  final List<String> summaryCalls = [];
  final List<ReportFilter> collectionsCalls = [];
  final List<ReportFilter> ledgerCalls = [];
  final List<ReportFilter> settlementsCalls = [];

  Future<void> _wait() async {
    if (hold != null) await hold!.future;
  }

  @override
  Future<FinanceSummary> summary(String propertyId) async {
    summaryCalls.add(propertyId);
    await _wait();
    if (summaryError != null) throw summaryError!;
    return summaryValue;
  }

  @override
  Future<List<CollectionRow>> collections(
    DateTime from,
    DateTime to,
    String propertyId,
  ) async {
    collectionsCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (collectionsError != null) throw collectionsError!;
    return collectionRows;
  }

  @override
  Future<List<LedgerRow>> ledger(
    DateTime from,
    DateTime to,
    String propertyId,
  ) async {
    ledgerCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (ledgerError != null) throw ledgerError!;
    return ledgerRows;
  }

  @override
  Future<List<SettlementRow>> settlements(
    DateTime from,
    DateTime to,
    String propertyId,
  ) async {
    settlementsCalls.add((from: from, to: to, propertyId: propertyId));
    await _wait();
    if (settlementsError != null) throw settlementsError!;
    return settlementRows;
  }
}

/// Resort R of the pgTAP file: slug `fin-r`, 12% tax, a GSTIN, today
/// 25 Sep 2026.
FinanceResort financeResort({
  String name = 'Resort R',
  String slug = 'fin-r',
  String? gstin = '29ABCDE1234F1Z5',
  num taxPct = 12,
  num fnbTaxPct = 0,
  num spaTaxPct = 0,
  String timezone = 'Asia/Kolkata',
  DateTime? today,
}) => FinanceResort(
  name: name,
  slug: slug,
  gstin: gstin,
  taxPct: taxPct,
  fnbTaxPct: fnbTaxPct,
  spaTaxPct: spaTaxPct,
  timezone: timezone,
  today: today ?? DateTime(2026, 9, 25),
);

/// A summary whose desk total and net are worked out from its parts.
FinanceSummary financeSummary({
  FinanceResort? resort,
  num online = 0,
  Map<PaymentMethod, num> desk = const {},
  num refunds = 0,
  num roomTax = 0,
  num foodTax = 0,
  num spaTax = 0,
  int inHouseCount = 0,
  num inHouseBalance = 0,
}) {
  final deskTotal = desk.values.fold<num>(0, (a, b) => a + b);
  return FinanceSummary(
    resort: resort ?? financeResort(),
    onlineCollected: online,
    deskCollected: deskTotal,
    deskByMethod: {for (final m in PaymentMethod.desk) m: desk[m] ?? 0},
    refunds: refunds,
    netCollected: online + deskTotal - refunds,
    roomTax: roomTax,
    foodTax: foodTax,
    spaTax: spaTax,
    inHouseCount: inHouseCount,
    inHouseBalance: inHouseBalance,
  );
}

/// Defaults to one online booking advance; override what a test is about.
CollectionRow collectionRow({
  DateTime? day,
  CollectionChannel channel = CollectionChannel.online,
  CollectionSource source = CollectionSource.bookingAdvance,
  PaymentMethod method = PaymentMethod.gateway,
  int txnCount = 1,
  num amount = 0,
}) => CollectionRow(
  day: day ?? DateTime(2026, 8, 1),
  channel: channel,
  source: source,
  method: method,
  txnCount: txnCount,
  amount: amount,
);

/// A ledger line whose taxable and net amounts follow from its parts.
LedgerRow ledgerRow({
  DateTime? day,
  LedgerCategory category = LedgerCategory.room,
  String source = 'booking',
  num gross = 0,
  num discount = 0,
  num tax = 0,
}) => LedgerRow(
  day: day ?? DateTime(2026, 8, 10),
  category: category,
  source: source,
  gross: gross,
  discount: discount,
  taxable: gross - discount,
  tax: tax,
  net: gross - discount + tax,
);

/// A settlement whose total defaults to the sum of its parts.
SettlementRow settlementRow({
  String reservationId = 'r1',
  String guestName = 'Gita Guest',
  String unitName = 'Cottage 1',
  DateTime? arrival,
  DateTime? departure,
  num room = 0,
  num cleaningFee = 0,
  num taxPct = 0,
  num tax = 0,
  num food = 0,
  num activities = 0,
  num? total,
  num advancePaid = 0,
  num balanceOnline = 0,
  num balanceDesk = 0,
  PaymentMethod? deskMethod,
  String? deskReference,
  String? recordedByName,
  num outstanding = 0,
}) => SettlementRow(
  reservationId: reservationId,
  guestName: guestName,
  unitName: unitName,
  arrival: arrival ?? DateTime(2026, 8, 10),
  departure: departure ?? DateTime(2026, 8, 12),
  room: room,
  cleaningFee: cleaningFee,
  taxPct: taxPct,
  tax: tax,
  food: food,
  activities: activities,
  total: total ?? room + cleaningFee + tax + food + activities,
  advancePaid: advancePaid,
  balanceOnline: balanceOnline,
  balanceDesk: balanceDesk,
  deskMethod: deskMethod,
  deskReference: deskReference,
  recordedByName: recordedByName,
  outstanding: outstanding,
);

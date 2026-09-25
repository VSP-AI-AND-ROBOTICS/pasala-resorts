import 'payment_method.dart';

DateTime _day(Object? raw) => DateTime.parse(raw as String);
num _money(Object? raw) => (raw as num?) ?? 0;

/// `report_collections.channel`. [online] is money that came through the
/// payment gateway (refunds go back the same way); [frontDesk] is money
/// taken at the desk, including walk-in sales.
enum CollectionChannel {
  online('online', 'Online'),
  frontDesk('front_desk', 'Front desk');

  const CollectionChannel(this.wire, this.label);
  final String wire;
  final String label;

  /// Unknown text is rejected, not defaulted: a silent fallback would hide a
  /// server/app mismatch in money figures.
  static CollectionChannel fromWire(String raw) => values.firstWhere(
    (c) => c.wire == raw,
    orElse: () => throw ArgumentError('Unknown collection channel: $raw'),
  );
}

/// `report_collections.source`: what the money was for.
enum CollectionSource {
  bookingAdvance('booking_advance', 'Booking advance'),
  checkoutBalance('checkout_balance', 'Checkout balance'),
  walkInSale('walk_in_sale', 'Walk-in sale'),
  refund('refund', 'Refund');

  const CollectionSource(this.wire, this.label);
  final String wire;
  final String label;

  static CollectionSource fromWire(String raw) => values.firstWhere(
    (s) => s.wire == raw,
    orElse: () => throw ArgumentError('Unknown collection source: $raw'),
  );
}

/// `report_ledger.category`: the revenue ledger a line belongs to.
enum LedgerCategory {
  room('room', 'Room'),
  foodBeverage('food_beverage', 'F&B'),
  spaActivities('spa_activities', 'Spa/Activities'),
  ancillary('ancillary', 'Ancillary');

  const LedgerCategory(this.wire, this.label);
  final String wire;
  final String label;

  static LedgerCategory fromWire(String raw) => values.firstWhere(
    (c) => c.wire == raw,
    orElse: () => throw ArgumentError('Unknown ledger category: $raw'),
  );
}

/// One row of `report_collections`: the money of one day, channel, source
/// and method (cash basis).
class CollectionRow {
  const CollectionRow({
    required this.day,
    required this.channel,
    required this.source,
    required this.method,
    required this.txnCount,
    required this.amount,
  });

  factory CollectionRow.fromJson(Map<String, dynamic> json) => CollectionRow(
    day: _day(json['day']),
    channel: CollectionChannel.fromWire(json['channel'] as String),
    source: CollectionSource.fromWire(json['source'] as String),
    method: PaymentMethod.fromWire(json['method'] as String?),
    txnCount: (json['txn_count'] as num?)?.toInt() ?? 0,
    amount: _money(json['amount']),
  );

  final DateTime day;
  final CollectionChannel channel;
  final CollectionSource source;
  final PaymentMethod method;
  final int txnCount;

  /// Negative for a refund.
  final num amount;
}

/// One row of `report_ledger`: revenue earned on one day, in one category,
/// from one source (accrual basis). `taxable = gross - discount` and
/// `net = taxable + tax`, both worked out server-side.
class LedgerRow {
  const LedgerRow({
    required this.day,
    required this.category,
    required this.source,
    required this.gross,
    required this.discount,
    required this.taxable,
    required this.tax,
    required this.net,
  });

  factory LedgerRow.fromJson(Map<String, dynamic> json) => LedgerRow(
    day: _day(json['day']),
    category: LedgerCategory.fromWire(json['category'] as String),
    source: json['source'] as String,
    gross: _money(json['gross']),
    discount: _money(json['discount']),
    taxable: _money(json['taxable']),
    tax: _money(json['tax']),
    net: _money(json['net']),
  );

  final DateTime day;
  final LedgerCategory category;

  /// `booking`, `cleaning_fee`, `cancellation_fee`, `in_stay_order`,
  /// `walk_in` or `activity_booking`. Shown only in the CSV.
  final String source;
  final num gross;
  final num discount;
  final num taxable;
  final num tax;
  final num net;
}

/// One row of `report_settlements`: a booking checked out in the range.
/// `room + cleaningFee + tax + food + activities == total`, and
/// `outstanding` is `total` minus every succeeded payment (0 after a normal
/// checkout).
class SettlementRow {
  const SettlementRow({
    required this.reservationId,
    required this.guestName,
    required this.unitName,
    required this.arrival,
    required this.departure,
    required this.room,
    required this.cleaningFee,
    required this.taxPct,
    required this.tax,
    required this.food,
    required this.activities,
    required this.total,
    required this.advancePaid,
    required this.balanceOnline,
    required this.balanceDesk,
    this.deskMethod,
    this.deskReference,
    this.recordedByName,
    required this.outstanding,
  });

  factory SettlementRow.fromJson(Map<String, dynamic> json) => SettlementRow(
    reservationId: json['reservation_id'] as String,
    guestName: json['guest_name'] as String,
    unitName: json['unit_name'] as String,
    arrival: _day(json['arrival']),
    departure: _day(json['departure']),
    room: _money(json['room']),
    cleaningFee: _money(json['cleaning_fee']),
    taxPct: _money(json['tax_pct']),
    tax: _money(json['tax']),
    food: _money(json['food']),
    activities: _money(json['activities']),
    total: _money(json['total']),
    advancePaid: _money(json['advance_paid']),
    balanceOnline: _money(json['balance_online']),
    balanceDesk: _money(json['balance_desk']),
    deskMethod: json['desk_method'] == null
        ? null
        : PaymentMethod.fromWire(json['desk_method'] as String),
    deskReference: json['desk_reference'] as String?,
    recordedByName: json['recorded_by_name'] as String?,
    outstanding: _money(json['outstanding']),
  );

  final String reservationId;
  final String guestName;
  final String unitName;
  final DateTime arrival;
  final DateTime departure;
  final num room;
  final num cleaningFee;
  final num taxPct;
  final num tax;
  final num food;
  final num activities;
  final num total;
  final num advancePaid;
  final num balanceOnline;
  final num balanceDesk;

  /// Null when the balance was paid online, or nothing was due.
  final PaymentMethod? deskMethod;
  final String? deskReference;

  /// Who recorded the balance payment.
  final String? recordedByName;
  final num outstanding;
}

/// The `resort` block of `finance_summary`: the export header and "today"
/// in the resort's own timezone.
class FinanceResort {
  const FinanceResort({
    required this.name,
    required this.slug,
    this.gstin,
    required this.taxPct,
    required this.timezone,
    required this.today,
  });

  factory FinanceResort.fromJson(Map<String, dynamic> json) => FinanceResort(
    name: json['name'] as String,
    slug: json['slug'] as String,
    gstin: json['gstin'] as String?,
    taxPct: _money(json['tax_pct']),
    timezone: json['timezone'] as String,
    today: _day(json['today']),
  );

  final String name;
  final String slug;
  final String? gstin;

  /// The resort's current rate; each booking's own rate is in its quote.
  final num taxPct;
  final String timezone;
  final DateTime today;
}

/// `finance_summary(p_property_id)`: today's money at one resort. Every
/// figure is worked out server-side; this class only parses. [refunds] is a
/// positive amount, and `netCollected = onlineCollected + deskCollected -
/// refunds`.
class FinanceSummary {
  const FinanceSummary({
    required this.resort,
    required this.onlineCollected,
    required this.deskCollected,
    required this.deskByMethod,
    required this.refunds,
    required this.netCollected,
    required this.roomTax,
    required this.inHouseCount,
    required this.inHouseBalance,
  });

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    final desk = (json['desk_collected'] as Map<String, dynamic>?) ?? const {};
    return FinanceSummary(
      resort: FinanceResort.fromJson(json['resort'] as Map<String, dynamic>),
      onlineCollected: _money(json['online_collected']),
      deskCollected: _money(desk['total']),
      deskByMethod: {
        for (final m in PaymentMethod.desk) m: _money(desk[m.wire]),
      },
      refunds: _money(json['refunds']),
      netCollected: _money(json['net_collected']),
      roomTax: _money(json['room_tax']),
      inHouseCount: (json['in_house_count'] as num?)?.toInt() ?? 0,
      inHouseBalance: _money(json['in_house_balance']),
    );
  }

  final FinanceResort resort;
  final num onlineCollected;

  /// Checkout balances taken at the desk plus walk-in sales.
  final num deskCollected;

  /// One entry per [PaymentMethod.desk] value, zero when none.
  final Map<PaymentMethod, num> deskByMethod;
  final num refunds;
  final num netCollected;

  /// Today's tax on bookings (room and cleaning-fee lines together).
  final num roomTax;
  final int inHouseCount;

  /// What the checked-in guests still owe, worked out as `current_charges`.
  final num inHouseBalance;
}

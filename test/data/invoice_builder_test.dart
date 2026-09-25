import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/invoice_builder.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';

const _id = '3f2a9c1b-0000-4000-8000-000000000001';
const _resort = InvoiceResort(
  name: 'Resort R',
  slug: 'fin-r',
  address: '12 Lake Road, Coorg',
  gstin: '29ABCDE1234F1Z5',
);
const _save10 = AppliedCoupon(
  code: 'SAVE10',
  kind: 'fixed',
  value: 1000,
  discount: 1000,
);

/// A stored quote as get_quote builds it: tax on subtotal + cleaning fee −
/// discount, total = that + tax.
Quote _quote({
  num subtotal = 10000,
  num cleaningFee = 500,
  AppliedCoupon? coupon = _save10,
  num taxPct = 12,
  int nights = 2,
}) {
  final discount = coupon?.discount ?? 0;
  final tax = (subtotal + cleaningFee - discount) * taxPct / 100;
  return Quote(
    currency: 'INR',
    guests: 2,
    lines: [
      for (var i = 0; i < nights; i++)
        QuoteLine(
          date: DateTime.utc(2026, 8, 10 + i),
          label: 'Weekday rate',
          amount: subtotal / nights,
          extraGuests: 0,
          extraGuestAmount: 0,
        ),
    ],
    subtotal: subtotal,
    cleaningFee: cleaningFee,
    coupon: coupon,
    taxPct: taxPct,
    taxAmount: tax,
    total: subtotal + cleaningFee - discount + tax,
  );
}

final _checkedOutAt = DateTime.utc(2026, 8, 12, 5, 30);
final _now = DateTime.utc(2026, 8, 11, 12);

Reservation _reservation({
  ReservationStatus status = ReservationStatus.checkedOut,
  ReservationKind kind = ReservationKind.booking,
  Quote? quote,
  String? customerName = 'Gita Guest',
}) => Reservation(
  id: _id,
  unitId: 'u1',
  start: DateTime.utc(2026, 8, 10, 8, 30),
  end: DateTime.utc(2026, 8, 12, 5, 30),
  kind: kind,
  status: status,
  customerId: 'g1',
  customerName: customerName,
  guests: 2,
  quote: quote ?? _quote(),
  checkedOutAt: status == ReservationStatus.checkedOut ? _checkedOutAt : null,
);

final _advance = InvoicePayment(
  kind: InvoicePaymentKind.advance,
  amount: 3192,
  method: PaymentMethod.gateway,
  reference: 'mock_abc',
  paidAt: DateTime.utc(2026, 8, 1, 4),
);
final _balance = InvoicePayment(
  kind: InvoicePaymentKind.balance,
  amount: 9468,
  method: PaymentMethod.cash,
  reference: 'R-17',
  paidAt: DateTime.utc(2026, 8, 12, 5),
);

const _food = [
  InvoiceCharge(amount: 525, taxAmount: 25, taxPct: 5),
  InvoiceCharge(amount: 315, taxAmount: 15, taxPct: 5),
];
const _spa = [InvoiceCharge(amount: 1180, taxAmount: 180, taxPct: 18)];

InvoiceInput _input({
  Reservation? reservation,
  InvoiceResort? resort = _resort,
  String? unitName = 'Cottage 1',
  bool dayUse = false,
  List<InvoiceCharge> food = _food,
  List<InvoiceCharge> activities = _spa,
  List<InvoicePayment>? payments,
  double total = 12660,
  double paid = 12660,
  double balance = 0,
}) => InvoiceInput(
  reservation: reservation ?? _reservation(),
  resort: resort,
  unitName: unitName,
  dayUse: dayUse,
  food: food,
  activities: activities,
  // Newest first on purpose: the invoice must sort them.
  payments: payments ?? [_balance, _advance],
  charges: CurrentCharges(
    stayAmount: 10640,
    foodAmount: 840,
    activityAmount: 1180,
    total: total,
    paid: paid,
    balance: balance,
  ),
  now: _now,
);

Matcher _refusal(String message) =>
    throwsA(isA<InvalidState>().having((e) => e.message, 'message', message));

void main() {
  test(
    'itemises room, cleaning fee, coupon, food and spa with tax per category',
    () {
      final invoice = buildInvoice(_input());
      expect(
        invoice.lines.map((l) => (l.kind, l.label, l.amount, l.tax, l.taxPct)),
        [
          (InvoiceLineKind.room, 'Room (2 nights)', 10000, 1080, 12),
          (InvoiceLineKind.cleaningFee, 'Cleaning fee', 500, 60, 12),
          (InvoiceLineKind.coupon, 'Coupon (SAVE10)', -1000, 0, null),
          (InvoiceLineKind.foodDrink, 'Food & Drink', 800, 40, 5),
          (InvoiceLineKind.spaActivities, 'Spa & Activities', 1000, 180, 18),
        ],
      );
      expect(invoice.subtotal, 11300);
      expect(invoice.taxTotal, 1360);
      expect(invoice.total, 12660);
      expect(invoice.paid, 12660);
      expect(invoice.amountDue, 0);
      expect(invoice.advancePaid, 3192);
      expect(invoice.resortName, 'Resort R');
      expect(invoice.resortAddress, '12 Lake Road, Coorg');
      expect(invoice.gstin, '29ABCDE1234F1Z5');
      expect(invoice.guestName, 'Gita Guest');
      expect(invoice.unitName, 'Cottage 1');
      expect(invoice.guests, 2);
    },
  );

  test('numbers the invoice from the resort slug and the reservation id', () {
    expect(buildInvoice(_input()).number, 'FIN-R-3F2A9C1B');
    expect(invoiceNumber('pasala', 'ab-cd'), 'PASALA-ABCD');
  });

  test('a checked-out booking is an Invoice dated at checkout', () {
    final invoice = buildInvoice(_input());
    expect(invoice.provisional, isFalse);
    expect(invoice.title, 'Invoice');
    expect(invoice.issuedAt, _checkedOutAt);
    expect(invoice.notes, [
      'Tax is charged on the room and cleaning fee after the coupon discount.',
    ]);
  });

  test('a checked-in booking is a provisional bill dated now', () {
    final invoice = buildInvoice(
      _input(reservation: _reservation(status: ReservationStatus.checkedIn)),
    );
    expect(invoice.provisional, isTrue);
    expect(invoice.issuedAt, _now);
    expect(
      invoice.notes,
      contains(
        'The stay is still in progress, so this bill may change before checkout.',
      ),
    );
  });

  for (final status in [
    ReservationStatus.hold,
    ReservationStatus.pendingPayment,
    ReservationStatus.confirmed,
    ReservationStatus.cancelled,
  ]) {
    test('refuses a ${status.name} booking', () {
      expect(
        () => buildInvoice(_input(reservation: _reservation(status: status))),
        _refusal('An invoice is available once the guest has checked in.'),
      );
    });
  }

  test('refuses admin blocks and OTA rows', () {
    for (final kind in [ReservationKind.block, ReservationKind.ota]) {
      expect(
        () => buildInvoice(_input(reservation: _reservation(kind: kind))),
        _refusal('Only guest bookings have an invoice.'),
      );
    }
  });

  test('refuses when the resort cannot be read', () {
    expect(
      () => buildInvoice(_input(resort: null)),
      _refusal(
        "This resort isn't taking bookings right now, so its invoice "
        "can't be issued. Contact the resort.",
      ),
    );
  });

  test('refuses a bill that changed between reads', () {
    expect(
      () => buildInvoice(_input(total: 13000)),
      _refusal(
        'The bill changed while the invoice was being prepared. Try again.',
      ),
    );
  });

  test('tolerates paise of float noise against current_charges', () {
    expect(buildInvoice(_input(total: 12660.004)).total, 12660);
  });

  test('rows without stored tax (before P4) count as untaxed', () {
    final invoice = buildInvoice(
      _input(
        food: const [InvoiceCharge(amount: 840)],
        activities: const [InvoiceCharge(amount: 1180)],
        total: 12660,
      ),
    );
    final food = invoice.lines.firstWhere(
      (l) => l.kind == InvoiceLineKind.foodDrink,
    );
    expect((food.amount, food.tax, food.taxPct), (840, 0, null));
  });

  test('shows a category rate only when every row shares it', () {
    final invoice = buildInvoice(
      _input(
        food: const [
          InvoiceCharge(amount: 525, taxAmount: 25, taxPct: 5),
          InvoiceCharge(amount: 315, taxAmount: 48.05, taxPct: 18),
        ],
      ),
    );
    final food = invoice.lines.firstWhere(
      (l) => l.kind == InvoiceLineKind.foodDrink,
    );
    expect(food.taxPct, isNull);
    expect(food.tax, 73.05);
    expect(food.amount, 766.95);
  });

  test('no coupon, no cleaning fee, nothing ordered: a single room line', () {
    final invoice = buildInvoice(
      _input(
        reservation: _reservation(
          quote: _quote(
            subtotal: 7000,
            cleaningFee: 0,
            coupon: null,
            taxPct: 0,
          ),
        ),
        food: const [],
        activities: const [],
        total: 7000,
      ),
    );
    expect(invoice.lines.map((l) => (l.label, l.amount, l.tax, l.taxPct)), [
      ('Room (2 nights)', 7000, 0, null),
    ]);
    expect(invoice.notes, isEmpty);
  });

  test('a slot booking is day use, one night is singular', () {
    expect(
      buildInvoice(_input(dayUse: true)).lines.first.label,
      'Room (day use)',
    );
    final oneNight = buildInvoice(
      _input(
        reservation: _reservation(
          quote: _quote(
            subtotal: 5000,
            cleaningFee: 0,
            coupon: null,
            taxPct: 0,
            nights: 1,
          ),
        ),
        food: const [],
        activities: const [],
        total: 5000,
      ),
    );
    expect(oneNight.lines.single.label, 'Room (1 night)');
  });

  test('a blank guest name prints as Guest', () {
    for (final name in [null, '', '   ']) {
      expect(
        buildInvoice(
          _input(reservation: _reservation(customerName: name)),
        ).guestName,
        'Guest',
      );
    }
  });

  test('payments are listed oldest first', () {
    final invoice = buildInvoice(_input());
    expect(invoice.payments.map((p) => p.kind), [
      InvoicePaymentKind.advance,
      InvoicePaymentKind.balance,
    ]);
  });

  test('a blank address or GSTIN becomes null', () {
    final invoice = buildInvoice(
      _input(
        resort: const InvoiceResort(
          name: 'Resort R',
          slug: 'fin-r',
          address: '  ',
          gstin: '',
        ),
      ),
    );
    expect(invoice.resortAddress, isNull);
    expect(invoice.gstin, isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/invoice_builder.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';

const _id = '3f2a9c1b-0000-4000-8000-000000000001';
const _props = {
  'name': 'Resort R',
  'slug': 'fin-r',
  'address': '12 Lake Road, Coorg',
  'gstin': '29ABCDE1234F1Z5',
};

Map<String, dynamic> _quoteJson() => {
  'currency': 'INR',
  'guests': 2,
  'lines': [
    {
      'date': '2026-08-10',
      'label': 'Weekday rate',
      'amount': 5000,
      'extra_guests': 0,
      'extra_guest_amount': 0,
    },
    {
      'date': '2026-08-11',
      'label': 'Weekday rate',
      'amount': 5000,
      'extra_guests': 0,
      'extra_guest_amount': 0,
    },
  ],
  'subtotal': 10000,
  'cleaning_fee': 500,
  'coupon': {
    'code': 'SAVE10',
    'kind': 'fixed',
    'value': 1000,
    'discount': 1000,
  },
  'tax_pct': 12,
  'tax_amount': 1140,
  'total': 10640,
};

/// A reservations row as `InvoiceRepository.reservationSelect` returns it.
Map<String, dynamic> _row({
  Map<String, dynamic>? properties = _props,
  Map<String, dynamic>? units = const {'name': 'Cottage 1'},
  String? slotTypeId,
}) => {
  'id': _id,
  'unit_id': 'u1',
  'property_id': 'p1',
  'period': '["2026-08-10 08:30:00+00","2026-08-12 05:30:00+00")',
  'kind': 'booking',
  'status': 'checked_out',
  'customer_id': 'g1',
  'guests': 2,
  'quote': _quoteJson(),
  'slot_type_id': slotTypeId,
  'checked_in_at': '2026-08-10T08:40:00+00:00',
  'checked_out_at': '2026-08-12T05:30:00+00:00',
  'created_at': '2026-08-01T04:00:00+00:00',
  'properties': properties,
  'units': units,
  'profiles': {'full_name': 'Gita Guest', 'phone': '9800000000'},
};

final _food = [
  {
    'id': 'f1',
    'total': 525,
    'status': 'delivered',
    'tax_amount': 25,
    'tax_pct': 5,
  },
  {
    'id': 'f2',
    'total': 315,
    'status': 'placed',
    'tax_amount': 15,
    'tax_pct': 5,
  },
];
final _activities = [
  {
    'id': 'a1',
    'amount': 1180,
    'status': 'booked',
    'tax_amount': 180,
    'tax_pct': 18,
  },
];
final _payments = [
  {
    'amount': 3192,
    'kind': 'advance',
    'method': 'gateway',
    'reference': null,
    'gateway_ref': 'mock_abc',
    'created_at': '2026-08-01T04:00:00+00:00',
  },
  {
    'amount': 9468,
    'kind': 'balance',
    'method': 'cash',
    'reference': ' R-17 ',
    'gateway_ref': 'desk-$_id',
    'created_at': '2026-08-12T05:30:00+00:00',
  },
];
const _charges = {
  'stay_amount': 10640,
  'food_amount': 840,
  'activity_amount': 1180,
  'total': 12660,
  'paid': 12660,
  'balance': 0,
};

InvoiceInput _parse({
  Map<String, dynamic>? row,
  List<dynamic>? food,
  List<dynamic>? activities,
  List<dynamic>? payments,
}) => InvoiceRepository.inputFrom(
  reservationRow: row ?? _row(),
  foodRows: food ?? _food,
  activityRows: activities ?? _activities,
  paymentRows: payments ?? _payments,
  chargesJson: _charges,
  now: DateTime.utc(2026, 9, 25),
);

void main() {
  test('selects the resort, unit and guest embeds it parses', () {
    expect(
      InvoiceRepository.reservationSelect,
      '*, properties(name, slug, address, gstin), units(name), '
      'profiles!reservations_customer_id_fkey(full_name, phone)',
    );
  });

  test('parses the reservation, the resort, the unit and the guest', () {
    final input = _parse();
    expect(input.reservation.id, _id);
    expect(input.reservation.customerName, 'Gita Guest');
    expect(input.reservation.quote!.subtotal, 10000);
    expect(input.resort!.name, 'Resort R');
    expect(input.resort!.slug, 'fin-r');
    expect(input.resort!.address, '12 Lake Road, Coorg');
    expect(input.resort!.gstin, '29ABCDE1234F1Z5');
    expect(input.unitName, 'Cottage 1');
    expect(input.dayUse, isFalse);
    expect(input.charges.total, 12660);
    expect(input.now, DateTime.utc(2026, 9, 25));
  });

  test('a resort hidden by RLS parses as no resort', () {
    final input = _parse(row: _row(properties: null, units: null));
    expect(input.resort, isNull);
    expect(input.unitName, isNull);
  });

  test('a slot booking is day use', () {
    expect(_parse(row: _row(slotTypeId: 'st1')).dayUse, isTrue);
  });

  test('food and activity rows carry their stored tax when present', () {
    final input = _parse(
      food: [
        ..._food,
        {
          'id': 'f3',
          'total': 300,
          'status': 'placed',
        }, // before P4: no tax columns
      ],
    );
    expect(input.food.map((c) => (c.amount, c.taxAmount, c.taxPct)), [
      (525, 25, 5),
      (315, 15, 5),
      (300, 0, null),
    ]);
    expect(input.activities.single.taxAmount, 180);
  });

  test(
    'online payments show the gateway id; desk payments the typed reference',
    () {
      final input = _parse(
        payments: [
          ..._payments,
          {
            'amount': 1,
            'kind': 'balance',
            'method': 'card',
            'reference': '  ',
            'gateway_ref': 'desk-x',
            'created_at': '2026-08-12T06:00:00+00:00',
          },
        ],
      );
      expect(input.payments.map((p) => (p.kind, p.method, p.reference)), [
        (InvoicePaymentKind.advance, PaymentMethod.gateway, 'mock_abc'),
        (InvoicePaymentKind.balance, PaymentMethod.cash, 'R-17'),
        (InvoicePaymentKind.balance, PaymentMethod.card, null),
      ]);
      expect(input.payments.first.paidAt, DateTime.utc(2026, 8, 1, 4));
    },
  );

  test('the parsed rows build the expected invoice', () {
    final invoice = buildInvoice(_parse());
    expect(invoice.number, 'FIN-R-3F2A9C1B');
    expect(invoice.total, 12660);
    expect(invoice.amountDue, 0);
  });
}

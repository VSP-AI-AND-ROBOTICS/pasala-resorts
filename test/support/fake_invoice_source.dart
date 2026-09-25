import 'dart:async';

import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';

/// In-memory [InvoiceSource]: answers [value], or throws [error]; [hold]
/// keeps calls pending; [calls] lists the reservation ids asked for.
class FakeInvoiceSource implements InvoiceSource {
  Invoice value = sampleInvoice();
  Object? error;
  Completer<void>? hold;
  final List<String> calls = [];

  @override
  Future<Invoice> invoice(String reservationId) async {
    calls.add(reservationId);
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return value;
  }
}

/// Resort R's invoice for a 2-night stay: ₹10,000 room + ₹500 cleaning,
/// coupon SAVE10 (−₹1,000), 12% room tax (₹1,080 + ₹60), food ₹840 incl.
/// ₹40 tax at 5%, spa ₹1,180 incl. ₹180 tax at 18% — total ₹12,660, paid
/// ₹3,192 online in advance and ₹9,468 in cash at checkout.
Invoice sampleInvoice({
  bool provisional = false,
  String number = 'FIN-R-3F2A9C1B',
  String guestName = 'Gita Guest',
  List<InvoiceLine>? lines,
  List<InvoicePayment>? payments,
  num paid = 12660,
  num amountDue = 0,
  List<String> notes = const [],
}) => Invoice(
  number: number,
  provisional: provisional,
  issuedAt: DateTime(2026, 8, 12, 11),
  resortName: 'Resort R',
  resortAddress: '12 Lake Road, Coorg',
  gstin: '29ABCDE1234F1Z5',
  guestName: guestName,
  unitName: 'Cottage 1',
  stayStart: DateTime(2026, 8, 10, 14),
  stayEnd: DateTime(2026, 8, 12, 11),
  guests: 2,
  lines:
      lines ??
      const [
        InvoiceLine(
          kind: InvoiceLineKind.room,
          label: 'Room (2 nights)',
          amount: 10000,
          tax: 1080,
          taxPct: 12,
        ),
        InvoiceLine(
          kind: InvoiceLineKind.cleaningFee,
          label: 'Cleaning fee',
          amount: 500,
          tax: 60,
          taxPct: 12,
        ),
        InvoiceLine(
          kind: InvoiceLineKind.coupon,
          label: 'Coupon (SAVE10)',
          amount: -1000,
        ),
        InvoiceLine(
          kind: InvoiceLineKind.foodDrink,
          label: 'Food & Drink',
          amount: 800,
          tax: 40,
          taxPct: 5,
        ),
        InvoiceLine(
          kind: InvoiceLineKind.spaActivities,
          label: 'Spa & Activities',
          amount: 1000,
          tax: 180,
          taxPct: 18,
        ),
      ],
  payments:
      payments ??
      [
        InvoicePayment(
          kind: InvoicePaymentKind.advance,
          amount: 3192,
          method: PaymentMethod.gateway,
          reference: 'mock_abc',
          paidAt: DateTime(2026, 8, 1, 9),
        ),
        InvoicePayment(
          kind: InvoicePaymentKind.balance,
          amount: 9468,
          method: PaymentMethod.cash,
          reference: 'R-17',
          paidAt: DateTime(2026, 8, 12, 11),
        ),
      ],
  paid: paid,
  amountDue: amountDue,
  notes: notes,
);

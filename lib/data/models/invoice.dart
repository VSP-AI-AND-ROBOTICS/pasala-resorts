import 'current_charges.dart';
import 'payment_method.dart';
import 'reservation.dart';

/// The resort block of an invoice, from the `properties` embed. Null in
/// [InvoiceInput.resort] when RLS hides the row (a guest of a resort that
/// is no longer active).
class InvoiceResort {
  const InvoiceResort({
    required this.name,
    required this.slug,
    this.address,
    this.gstin,
  });

  final String name;
  final String slug;
  final String? address;
  final String? gstin;
}

/// One non-cancelled food order or activity booking: its tax-inclusive
/// amount and the tax stored on it (P4's `tax_amount`/`tax_pct`; 0 and null
/// on rows from before P4).
class InvoiceCharge {
  const InvoiceCharge({required this.amount, this.taxAmount = 0, this.taxPct});

  final num amount;
  final num taxAmount;
  final num? taxPct;
}

/// `public.payment_kind`.
enum InvoicePaymentKind {
  advance('Advance'),
  balance('Balance');

  const InvoicePaymentKind(this.label);
  final String label;

  static InvoicePaymentKind fromWire(String raw) =>
      raw == 'advance' ? advance : balance;
}

/// One succeeded payment as printed on the invoice.
class InvoicePayment {
  const InvoicePayment({
    required this.kind,
    required this.amount,
    required this.method,
    this.reference,
    required this.paidAt,
  });

  final InvoicePaymentKind kind;
  final num amount;
  final PaymentMethod method;

  /// The receipt/UTR typed at the desk, or the gateway's payment id for an
  /// online payment. Null when blank.
  final String? reference;
  final DateTime paidAt;
}

/// Everything `buildInvoice` needs, as read from the server.
class InvoiceInput {
  const InvoiceInput({
    required this.reservation,
    required this.resort,
    required this.unitName,
    required this.dayUse,
    required this.food,
    required this.activities,
    required this.payments,
    required this.charges,
    required this.now,
  });

  /// With `customerName` from the `profiles` embed.
  final Reservation reservation;
  final InvoiceResort? resort;
  final String? unitName;

  /// A slot booking (`reservations.slot_type_id` set).
  final bool dayUse;
  final List<InvoiceCharge> food;
  final List<InvoiceCharge> activities;
  final List<InvoicePayment> payments;
  final CurrentCharges charges;

  /// The provisional bill's date.
  final DateTime now;
}

enum InvoiceLineKind { room, cleaningFee, coupon, foodDrink, spaActivities }

/// One charge line: [amount] excludes tax, [tax] is the tax on it.
class InvoiceLine {
  const InvoiceLine({
    required this.kind,
    required this.label,
    required this.amount,
    this.tax = 0,
    this.taxPct,
  });

  final InvoiceLineKind kind;
  final String label;
  final num amount;
  final num tax;

  /// Shown next to the tax; null when there is no single rate.
  final num? taxPct;

  num get total => amount + tax;
}

/// A booking invoice ready to lay out. Built only by `buildInvoice`, which
/// guarantees [total] equals `current_charges.total`.
class Invoice {
  const Invoice({
    required this.number,
    required this.provisional,
    required this.issuedAt,
    required this.resortName,
    this.resortAddress,
    this.gstin,
    required this.guestName,
    this.unitName,
    required this.stayStart,
    required this.stayEnd,
    this.guests,
    required this.lines,
    required this.payments,
    required this.paid,
    required this.amountDue,
    this.notes = const [],
  });

  /// `PASALA-3F2A9C1B`.
  final String number;

  /// A checked-in stay's running bill rather than the final invoice.
  final bool provisional;
  final DateTime issuedAt;
  final String resortName;
  final String? resortAddress;
  final String? gstin;
  final String guestName;
  final String? unitName;
  final DateTime stayStart;
  final DateTime stayEnd;
  final int? guests;
  final List<InvoiceLine> lines;

  /// Oldest first.
  final List<InvoicePayment> payments;

  /// `current_charges.paid`.
  final num paid;

  /// `current_charges.balance`.
  final num amountDue;
  final List<String> notes;

  String get title => provisional ? 'Provisional bill' : 'Invoice';
  String get fileName => 'invoice-$number.pdf';
  num get subtotal => lines.fold<num>(0, (a, l) => a + l.amount);
  num get taxTotal => lines.fold<num>(0, (a, l) => a + l.tax);
  num get total => lines.fold<num>(0, (a, l) => a + l.total);
  num get advancePaid => payments
      .where((p) => p.kind == InvoicePaymentKind.advance)
      .fold<num>(0, (a, p) => a + p.amount);
}

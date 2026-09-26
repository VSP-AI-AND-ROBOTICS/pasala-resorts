import 'dart:math' as math;

import '../../core/errors.dart';
import 'invoice.dart';
import 'reservation.dart';

/// `pasala` + `3f2a9c1b-…` -> `PASALA-3F2A9C1B`: the same for every viewer,
/// from stored ids only.
String invoiceNumber(String slug, String reservationId) {
  final hex = reservationId.replaceAll('-', '');
  final short = hex.length >= 8 ? hex.substring(0, 8) : hex;
  return '${slug.toUpperCase()}-${short.toUpperCase()}';
}

num _r2(num v) => (v * 100).round() / 100;
num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);
String? _blankToNull(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

/// The rate every row shares, or null (none, mixed, or zero).
num? _uniformPct(List<InvoiceCharge> rows) {
  final pcts = rows.map((r) => r.taxPct).toSet();
  if (pcts.length != 1) return null;
  final pct = pcts.single;
  return (pct == null || pct == 0) ? null : pct;
}

String _roomLabel(InvoiceInput input) {
  if (input.dayUse) return 'Room (day use)';
  final nights = input.reservation.quote!.lines.length;
  return 'Room ($nights ${nights == 1 ? 'night' : 'nights'})';
}

/// Builds the invoice of [input] (spec Decisions 3–7, 11). Never
/// recomputes a price: room figures come from the stored quote, food and
/// activities from their rows, and the lines must add up to
/// `current_charges.total` or the invoice is refused.
Invoice buildInvoice(InvoiceInput input) {
  final r = input.reservation;
  if (r.kind != ReservationKind.booking) {
    throw const InvalidState('Only guest bookings have an invoice.');
  }
  final provisional = switch (r.status) {
    ReservationStatus.checkedOut => false,
    ReservationStatus.checkedIn => true,
    _ => throw const InvalidState(
      'An invoice is available once the guest has checked in.',
    ),
  };
  final resort = input.resort;
  if (resort == null) {
    throw const InvalidState(
      "This resort isn't taking bookings right now, "
      "so its invoice can't be issued. Contact the resort.",
    );
  }

  final lines = <InvoiceLine>[];
  final notes = <String>[];
  final q = r.quote;
  if (q != null) {
    // The same split report_ledger (0048) makes: the room line is taxed on
    // subtotal minus the part of the discount it absorbs; the cleaning fee
    // carries the rest of the quote's tax, so the two add up exactly.
    final discount = q.coupon?.discount ?? 0;
    final roomDiscount = math.min(discount, q.subtotal);
    final roomTax = _r2((q.subtotal - roomDiscount) * q.taxPct / 100);
    final cleaningTax = _r2(q.taxAmount - roomTax);
    final pct = q.taxPct == 0 ? null : q.taxPct;
    lines.add(
      InvoiceLine(
        kind: InvoiceLineKind.room,
        label: _roomLabel(input),
        amount: q.subtotal,
        tax: roomTax,
        taxPct: pct,
      ),
    );
    if (q.cleaningFee != 0 || cleaningTax != 0) {
      lines.add(
        InvoiceLine(
          kind: InvoiceLineKind.cleaningFee,
          label: 'Cleaning fee',
          amount: q.cleaningFee,
          tax: cleaningTax,
          taxPct: pct,
        ),
      );
    }
    if (q.coupon != null) {
      lines.add(
        InvoiceLine(
          kind: InvoiceLineKind.coupon,
          label: 'Coupon (${q.coupon!.code})',
          amount: -discount,
        ),
      );
      if (q.taxAmount != 0) {
        notes.add(
          'Tax is charged on the room and cleaning fee after the coupon discount.',
        );
      }
    }
  }

  // Food and activity prices include their tax (P4).
  void addCategory(
    InvoiceLineKind kind,
    String label,
    List<InvoiceCharge> rows,
  ) {
    if (rows.isEmpty) return;
    final gross = _sum(rows.map((c) => c.amount));
    final tax = _sum(rows.map((c) => c.taxAmount));
    lines.add(
      InvoiceLine(
        kind: kind,
        label: label,
        amount: _r2(gross - tax),
        tax: _r2(tax),
        taxPct: _uniformPct(rows),
      ),
    );
  }

  addCategory(InvoiceLineKind.foodDrink, 'Food & Drink', input.food);
  addCategory(
    InvoiceLineKind.spaActivities,
    'Spa & Activities',
    input.activities,
  );

  final total = _sum(lines.map((l) => l.total));
  if ((total - input.charges.total).abs() > 0.01) {
    throw const InvalidState(
      'The bill changed while the invoice was being prepared. Try again.',
    );
  }

  if (provisional) {
    notes.add(
      'The stay is still in progress, so this bill may change before checkout.',
    );
  }

  final payments = [...input.payments]
    ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

  return Invoice(
    number: invoiceNumber(resort.slug, r.id),
    provisional: provisional,
    issuedAt: provisional ? input.now : (r.checkedOutAt ?? input.now),
    resortName: resort.name,
    resortAddress: _blankToNull(resort.address),
    gstin: _blankToNull(resort.gstin),
    guestName: _blankToNull(r.customerName) ?? 'Guest',
    unitName: _blankToNull(input.unitName),
    stayStart: r.start,
    stayEnd: r.end,
    guests: r.guests,
    lines: lines,
    payments: payments,
    paid: input.charges.paid,
    amountDue: input.charges.balance,
    notes: notes,
  );
}

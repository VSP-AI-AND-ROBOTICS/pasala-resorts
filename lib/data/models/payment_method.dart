import 'package:flutter/material.dart';

/// How money reached the resort -- `public.payment_method`
/// (0048_finance_ledger.sql). [gateway] is every payment taken online (and
/// the default of every payment written before 0048); the other five are
/// desk methods, recorded by resort staff at checkout or on a walk-in sale.
enum PaymentMethod {
  gateway('gateway', 'Online', Icons.language),
  cash('cash', 'Cash', Icons.payments_outlined),
  card('card', 'Card', Icons.credit_card),
  upi('upi', 'UPI', Icons.qr_code_2),
  bankTransfer(
    'bank_transfer',
    'Bank transfer',
    Icons.account_balance_outlined,
  ),
  other('other', 'Other', Icons.more_horiz);

  const PaymentMethod(this.wire, this.label, this.icon);

  /// The Postgres enum label.
  final String wire;
  final String label;
  final IconData icon;

  /// Every method a person records at the desk, in chip order: all but
  /// [gateway].
  static const desk = [cash, card, upi, bankTransfer, other];

  /// Unknown or missing text parses as [other]: a money row must still show
  /// up in a report even if a later migration adds a method this build does
  /// not know yet.
  static PaymentMethod fromWire(String? raw) {
    for (final m in values) {
      if (m.wire == raw) return m;
    }
    return other;
  }
}

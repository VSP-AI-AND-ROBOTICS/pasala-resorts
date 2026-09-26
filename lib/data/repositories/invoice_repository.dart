import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/current_charges.dart';
import '../models/invoice.dart';
import '../models/invoice_builder.dart';
import '../models/payment_method.dart';
import '../models/reservation.dart';

/// The slice of [InvoiceRepository] the invoice button needs. Tests
/// override [invoiceSourceProvider] with `FakeInvoiceSource`.
abstract class InvoiceSource {
  /// The invoice of [reservationId], read afresh on every call. Throws a
  /// `BookingFailure`: the server's refusal, or `InvalidState` from
  /// `buildInvoice`.
  Future<Invoice> invoice(String reservationId);
}

/// Reads an invoice with the viewer's own rights -- no new SQL: the
/// reservation and its resort/unit/guest embeds, its non-cancelled food
/// orders and activity bookings, its succeeded payments (all under the RLS
/// of 0044_resort_policies.sql: the guest who owns it, or staff of its
/// resort) and `current_charges`, which applies the same rule.
class InvoiceRepository implements InvoiceSource {
  InvoiceRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SupabaseClient _db;
  final DateTime Function() _clock;

  static const reservationSelect =
      '*, properties(name, slug, address, gstin), units(name), '
      'profiles!reservations_customer_id_fkey(full_name, phone)';

  @override
  Future<Invoice> invoice(String reservationId) async {
    try {
      final results = await Future.wait<Object?>([
        _db
            .from('reservations')
            .select(reservationSelect)
            .eq('id', reservationId)
            .single(),
        _db
            .from('food_orders')
            .select()
            .eq('reservation_id', reservationId)
            .neq('status', 'cancelled'),
        _db
            .from('activity_bookings')
            .select()
            .eq('reservation_id', reservationId)
            .neq('status', 'cancelled'),
        _db
            .from('payments')
            .select('amount, kind, method, reference, gateway_ref, created_at')
            .eq('reservation_id', reservationId)
            .eq('status', 'succeeded')
            .order('created_at', ascending: true),
        _db.rpc('current_charges', params: {'p_reservation_id': reservationId}),
      ]);
      return buildInvoice(
        inputFrom(
          reservationRow: results[0]! as Map<String, dynamic>,
          foodRows: results[1]! as List<dynamic>,
          activityRows: results[2]! as List<dynamic>,
          paymentRows: results[3]! as List<dynamic>,
          chargesJson: results[4]! as Map<String, dynamic>,
          now: _clock(),
        ),
      );
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// Parses the five reads. `tax_amount`/`tax_pct` are P4's columns on
  /// food_orders and activity_bookings; rows without them are untaxed.
  static InvoiceInput inputFrom({
    required Map<String, dynamic> reservationRow,
    required List<dynamic> foodRows,
    required List<dynamic> activityRows,
    required List<dynamic> paymentRows,
    required Map<String, dynamic> chargesJson,
    required DateTime now,
  }) {
    final property = reservationRow['properties'] as Map<String, dynamic>?;
    final unit = reservationRow['units'] as Map<String, dynamic>?;
    return InvoiceInput(
      reservation: Reservation.fromJson(reservationRow),
      resort: property == null
          ? null
          : InvoiceResort(
              name: property['name'] as String,
              slug: property['slug'] as String,
              address: property['address'] as String?,
              gstin: property['gstin'] as String?,
            ),
      unitName: unit?['name'] as String?,
      dayUse: reservationRow['slot_type_id'] != null,
      food: [
        for (final r in foodRows.cast<Map<String, dynamic>>())
          _charge(r, 'total'),
      ],
      activities: [
        for (final r in activityRows.cast<Map<String, dynamic>>())
          _charge(r, 'amount'),
      ],
      payments: [
        for (final p in paymentRows.cast<Map<String, dynamic>>()) _payment(p),
      ],
      charges: CurrentCharges.fromJson(chargesJson),
      now: now,
    );
  }

  static InvoiceCharge _charge(Map<String, dynamic> row, String amountKey) =>
      InvoiceCharge(
        amount: row[amountKey] as num,
        taxAmount: (row['tax_amount'] as num?) ?? 0,
        taxPct: row['tax_pct'] as num?,
      );

  static InvoicePayment _payment(Map<String, dynamic> row) {
    final method = PaymentMethod.fromWire(row['method'] as String?);
    // A desk payment's gateway_ref is the internal 'desk-<id>' retry guard;
    // what the guest recognises is the receipt/UTR typed into `reference`.
    final raw =
        (method == PaymentMethod.gateway
                ? row['gateway_ref']
                : row['reference'])
            as String?;
    final reference = raw?.trim();
    return InvoicePayment(
      kind: InvoicePaymentKind.fromWire(row['kind'] as String),
      amount: row['amount'] as num,
      method: method,
      reference: (reference == null || reference.isEmpty) ? null : reference,
      paidAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(supabaseProvider)),
);

/// The [InvoiceSource] seam every screen calls through.
final invoiceSourceProvider = Provider<InvoiceSource>(
  (ref) => ref.watch(invoiceRepositoryProvider),
);

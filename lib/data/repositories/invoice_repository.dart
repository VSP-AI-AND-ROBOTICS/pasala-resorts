import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/invoice.dart';

/// The slice of [InvoiceRepository] the invoice button needs. Tests
/// override [invoiceSourceProvider] with `FakeInvoiceSource`.
abstract class InvoiceSource {
  /// The invoice of [reservationId], read afresh on every call. Throws a
  /// `BookingFailure`: the server's refusal, or `InvalidState` from
  /// `buildInvoice`.
  Future<Invoice> invoice(String reservationId);
}

class InvoiceRepository implements InvoiceSource {
  InvoiceRepository(this._db);

  // ignore: unused_field
  final SupabaseClient _db;

  @override
  Future<Invoice> invoice(String reservationId) =>
      throw UnimplementedError('InvoiceRepository.invoice lands in P2 Task 3');
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(supabaseProvider)),
);

/// The [InvoiceSource] seam every screen calls through.
final invoiceSourceProvider = Provider<InvoiceSource>(
  (ref) => ref.watch(invoiceRepositoryProvider),
);

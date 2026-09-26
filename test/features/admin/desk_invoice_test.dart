import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/desk_invoice.dart';

void main() {
  // The check-out banner hides Download invoice while this is null; once
  // the invoice PDF feature (P2) is merged it must be bound.
  test('the desk invoice download is bound to the invoice PDF feature', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(deskInvoiceDownloadProvider), isNotNull);
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../invoice/invoice_pdf_button.dart';

/// Saves one booking's invoice PDF for reception, after a desk checkout.
///
/// Gets the check-out banner's own [context] and [ref] so that the binding
/// below can call the invoice PDF entry point (P2) with whatever it needs.
typedef DeskInvoiceDownload =
    Future<void> Function(
      BuildContext context,
      WidgetRef ref,
      String reservationId,
    );

/// Bound to the invoice PDF feature (P2): builds this booking's invoice PDF
/// and saves it (a `.pdf` download on the web), reporting the outcome in a
/// SnackBar. A provider, like `csvDownloaderProvider`, so widget tests can
/// capture the call.
final deskInvoiceDownloadProvider = Provider<DeskInvoiceDownload?>(
  (ref) => downloadInvoicePdf,
);

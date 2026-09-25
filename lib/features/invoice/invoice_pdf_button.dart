import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/pdf/pdf_delivery.dart';
import '../../core/pdf/pdf_exporter.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/invoice_repository.dart';

/// Reads, renders and delivers the invoice of [reservationId], reporting
/// the outcome in a SnackBar. Everything it needs is read before the first
/// await, so it still finishes and reports if the calling widget is gone by
/// then (P5 calls it from reception's post-checkout SnackBar action).
Future<void> downloadInvoicePdf(
  BuildContext context,
  WidgetRef ref,
  String reservationId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final source = ref.read(invoiceSourceProvider);
  final exporter = ref.read(pdfExporterProvider);
  final deliver = ref.read(pdfDelivererProvider);
  void show(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  try {
    final invoice = await source.invoice(reservationId);
    final bytes = await exporter.invoice(invoice);
    final delivered = await deliver(invoice.fileName, bytes);
    show(
      delivered
          ? 'Invoice ${invoice.number} is ready.'
          : "Invoice download isn't available on this device yet.",
    );
  } on BookingFailure catch (e) {
    show(FailureView.messageFor(e));
  } catch (_) {
    show("Couldn't create the invoice PDF. Try again.");
  }
}

enum InvoicePdfButtonStyle { button, icon }

/// "Download invoice (PDF)" (full width in a card) or a compact "Invoice
/// PDF" icon for list rows. Disabled, with a spinner, while working.
class InvoicePdfButton extends ConsumerStatefulWidget {
  const InvoicePdfButton({
    super.key,
    required this.reservationId,
    this.style = InvoicePdfButtonStyle.button,
  });

  final String reservationId;
  final InvoicePdfButtonStyle style;

  @override
  ConsumerState<InvoicePdfButton> createState() => _InvoicePdfButtonState();
}

class _InvoicePdfButtonState extends ConsumerState<InvoicePdfButton> {
  bool _busy = false;

  static const _spinner = SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await downloadInvoicePdf(context, ref, widget.reservationId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.style) {
    InvoicePdfButtonStyle.icon => IconButton(
      key: Key('invoice-pdf-${widget.reservationId}'),
      tooltip: 'Invoice PDF',
      onPressed: _busy ? null : _download,
      icon: _busy ? _spinner : const Icon(Icons.picture_as_pdf_outlined),
    ),
    InvoicePdfButtonStyle.button => OutlinedButton.icon(
      key: const Key('invoice-pdf-button'),
      onPressed: _busy ? null : _download,
      icon: _busy ? _spinner : const Icon(Icons.picture_as_pdf_outlined),
      label: Text(_busy ? 'Preparing invoice…' : 'Download invoice (PDF)'),
    ),
  };
}

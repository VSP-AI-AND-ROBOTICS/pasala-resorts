import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import 'desk_invoice.dart';

/// The first 8 characters of a reservation id, the "Booking abcd1234" form
/// `FinalInvoiceScreen` uses. A shorter id (a hand-edited URL) is shown whole.
String shortBookingId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// The success message on reception's check-out list after a desk checkout
/// (`/admin/check-out?checkedOut=<id>`), with the booking's invoice PDF one
/// tap away. It lives in the URL, so a reload keeps it. It goes when
/// dismissed, when another guest is checked out, or when reception leaves
/// the list.
class DeskCheckoutBanner extends ConsumerStatefulWidget {
  const DeskCheckoutBanner({
    super.key,
    required this.reservationId,
    required this.onDismiss,
  });

  final String reservationId;
  final VoidCallback onDismiss;

  @override
  ConsumerState<DeskCheckoutBanner> createState() => _DeskCheckoutBannerState();
}

class _DeskCheckoutBannerState extends ConsumerState<DeskCheckoutBanner> {
  bool _busy = false;

  Future<void> _download(DeskInvoiceDownload download) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await download(context, ref, widget.reservationId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FailureView.messageFor(mapPostgrestError(e)))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final download = ref.watch(deskInvoiceDownloadProvider);
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        key: const Key('desk-checkout-done'),
        color: theme.colorScheme.primaryContainer,
        margin: const EdgeInsets.fromLTRB(
          Spacing.md,
          Spacing.md,
          Spacing.md,
          0,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.xs,
            Spacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Icon(Icons.check_circle_outline, color: onContainer),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Guest checked out',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: onContainer,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Booking ${shortBookingId(widget.reservationId)} is settled.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onContainer,
                      ),
                    ),
                    if (download != null)
                      TextButton.icon(
                        key: const Key('desk-invoice-download'),
                        onPressed: _busy ? null : () => _download(download),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                          _busy ? 'Preparing invoice…' : 'Download invoice',
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close, color: onContainer),
                onPressed: widget.onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

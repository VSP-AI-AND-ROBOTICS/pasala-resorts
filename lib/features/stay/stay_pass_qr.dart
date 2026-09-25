import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../data/repositories/stay_pass_repository.dart';
import '../admin/admin_bookings_screen.dart' show bookingCode;

/// The guest's signed check-in pass (P3) as a QR code that reception
/// scans, with the booking code underneath for reception to type when the
/// camera cannot read it. If the pass cannot be loaded (offline, or the
/// booking is not confirmed yet) the box shows a retry button and the
/// booking code still shows. [compact] draws only the QR box, for a small
/// thumbnail.
class StayPassQr extends ConsumerWidget {
  const StayPassQr({
    super.key,
    required this.reservationId,
    this.size = 140,
    this.compact = false,
  });

  final String reservationId;
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pass = ref.watch(stayPassProvider(reservationId));
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final box = Container(
      padding: EdgeInsets.all(compact ? Spacing.xs : Spacing.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
      ),
      child: SizedBox.square(
        dimension: size,
        child: pass.when(
          data: (token) => QrImageView(
            key: const Key('stay-pass-qr'),
            data: token,
            size: size,
            padding: EdgeInsets.zero,
            backgroundColor: Colors.white,
            semanticsLabel: 'Check-in pass QR code',
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: IconButton(
              key: const Key('stay-pass-retry'),
              tooltip: 'Try again',
              icon: const Icon(Icons.refresh, color: Colors.black54),
              onPressed: () => ref.invalidate(stayPassProvider(reservationId)),
            ),
          ),
        ),
      ),
    );
    if (compact) return box;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        if (pass.hasError && !pass.isLoading) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            "Couldn't load your pass. Show the booking code at the desk.",
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: Spacing.xs),
        Text(
          'Booking code ${bookingCode(reservationId)}',
          style: textTheme.labelLarge,
        ),
      ],
    );
  }
}

/// My Stay's small pass. At 64 px the QR is too dense to scan, so a tap
/// opens it full size ([showStayPassDialog]).
class StayPassThumbnail extends StatelessWidget {
  const StayPassThumbnail({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Show check-in pass',
        child: InkWell(
          key: const Key('stay-pass-thumbnail'),
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
          onTap: () => showStayPassDialog(context, reservationId),
          child: StayPassQr(
            reservationId: reservationId,
            size: 64,
            compact: true,
          ),
        ),
      );
}

/// The pass full size in a dialog (200 px fits a 360-px-wide phone). The
/// dialog closes itself with its own context.
Future<void> showStayPassDialog(BuildContext context, String reservationId) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Check-in pass'),
        content: StayPassQr(reservationId: reservationId, size: 200),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );

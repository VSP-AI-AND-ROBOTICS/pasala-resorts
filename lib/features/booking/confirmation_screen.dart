import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/hero_backdrop.dart';
import '../../data/models/reservation.dart';
import '../stay/stay_pass_qr.dart';
import 'providers.dart';

class ConfirmationScreen extends ConsumerWidget {
  const ConfirmationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking confirmed')),
      body: AsyncView(
        value: reservationAsync,
        onRetry: () => ref.invalidate(reservationProvider(reservationId)),
        data: (reservation) => _Confirmed(reservation: reservation),
      ),
    );
  }
}

class _Confirmed extends ConsumerWidget {
  const _Confirmed({required this.reservation});

  final Reservation reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(unitByIdProvider(reservation.unitId));
    final quote = reservation.quote;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return HeroBackdrop(
      imageAsset: AppAssets.eventStringLights,
      scrimOpacity: 0.7,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.xl),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                // The QR code (added for the Guest Stay Experience feature)
                // pushes this card's natural height past what a short
                // viewport (a landscape phone, a small desktop window) can
                // offer -- scrollable rather than overflowing, since the
                // card's own height is already driven purely by its
                // content, never fixed.
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: PasalaTokens.motionBase,
                        curve: Curves.elasticOut,
                        builder: (context, value, child) =>
                            Transform.scale(scale: value, child: child),
                        child: Container(
                          padding: const EdgeInsets.all(Spacing.md),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_circle,
                            color: scheme.onPrimaryContainer,
                            size: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: Spacing.lg),
                      Text(
                        unitAsync.value?.name ?? 'Your booking',
                        style: textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.sm),
                      Text(
                        '${formatDay(reservation.start.toLocal())} – '
                        '${formatDay(reservation.end.toLocal())}',
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (reservation.occasion != null &&
                          reservation.occasion!.trim().isNotEmpty) ...[
                        const SizedBox(height: Spacing.sm),
                        Text(
                          'For: ${reservation.occasion}',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (quote != null) ...[
                        const SizedBox(height: Spacing.sm),
                        Text(
                          formatInr(quote.total),
                          style: textTheme.titleLarge?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: Spacing.lg),
                      // The signed check-in pass reception scans (P3).
                      StayPassQr(reservationId: reservation.id),
                      const SizedBox(height: Spacing.xs),
                      Text(
                        'Show this at check-in',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: Spacing.xl),
                      FilledButton(
                        onPressed: () => context.go('/bookings'),
                        child: const Text('View my bookings'),
                      ),
                      const SizedBox(height: Spacing.sm),
                      OutlinedButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Browse more'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

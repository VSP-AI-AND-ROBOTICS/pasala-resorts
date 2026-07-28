import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/reservation.dart';
import 'providers.dart';

class ConfirmationScreen extends ConsumerWidget {
  const ConfirmationScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationAsync = ref.watch(reservationProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Booking confirmed')),
      body: reservationAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(reservationProvider(reservationId)),
        ),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle,
                  color: Theme.of(context).colorScheme.primary, size: 64),
              const SizedBox(height: 16),
              Text(
                unitAsync.value?.name ?? 'Your booking',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${formatDay(reservation.start.toLocal())} – '
                '${formatDay(reservation.end.toLocal())}',
                textAlign: TextAlign.center,
              ),
              if (quote != null) ...[
                const SizedBox(height: 8),
                Text(
                  formatInr(quote.total),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => context.go('/bookings'),
                child: const Text('View my bookings'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => context.go('/'),
                child: const Text('Browse more'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

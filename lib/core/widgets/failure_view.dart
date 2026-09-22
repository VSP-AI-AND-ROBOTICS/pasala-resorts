import 'package:flutter/material.dart';

import '../errors.dart';

/// Shared error rendering for every `AsyncValue.error` branch in the app.
///
/// [UnitUnavailable], [HoldExpired], [QuoteStale], [NotPermitted], [NotFound],
/// [InvalidState] and [NetworkFailure] all carry a message that was written
/// for a customer to read, so those are shown verbatim. [UnknownFailure] is
/// the one exception: it wraps whatever raw text Postgres or the transport
/// layer produced (see `mapPostgrestError`), which can include schema and
/// permission detail that must never reach the screen -- so it is mapped to
/// the same generic fallback as any error this app doesn't even recognise as
/// a [BookingFailure].
class FailureView extends StatelessWidget {
  const FailureView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  static const _generic = 'Something went wrong.';

  /// Pure so the "never leaks raw server text" guarantee is checkable
  /// without pumping a widget.
  static String messageFor(Object error) => switch (error) {
        UnknownFailure() => _generic,
        BookingFailure(:final message) => message,
        _ => _generic,
      };

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                messageFor(error),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      );
}

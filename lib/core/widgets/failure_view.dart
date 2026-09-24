import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../current_resort.dart';
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
///
/// A [NotAMember] failure gets one extra bit of behaviour on top of just
/// showing its message: the current resort was a stale, since-revoked pick
/// (Review Focus #4), so once the message is on screen this also forgets it
/// and re-fetches the user, via [handleResortAccessLost] -- the router then
/// re-runs `landingPathFor` against the refreshed memberships. Scheduled for
/// after the first frame (not run inline in `build`) since it changes
/// provider state, which must never happen while the widget tree is still
/// being built.
class FailureView extends StatefulWidget {
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
  State<FailureView> createState() => _FailureViewState();
}

class _FailureViewState extends State<FailureView> {
  @override
  void initState() {
    super.initState();
    if (widget.error is NotAMember) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(handleResortAccessLost(ProviderScope.containerOf(context)));
      });
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FailureView.messageFor(widget.error),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: widget.onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      );
}

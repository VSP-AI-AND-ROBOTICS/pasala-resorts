import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'failure_view.dart';
import 'loading_state.dart';

/// The single place an [AsyncValue] is unwrapped in this app.
///
/// Centralising it means loading and error presentation cannot drift between
/// screens, and no screen can accidentally render a raw error object — the
/// error branch always goes through [FailureView], which strips server text
/// from an [UnknownFailure].
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.empty,
    this.onRetry,
    this.loadingMessage,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final Widget Function()? empty;
  final VoidCallback? onRetry;
  final String? loadingMessage;

  @override
  Widget build(BuildContext context) => value.when(
        loading: () => LoadingState(message: loadingMessage),
        error: (error, _) => FailureView(error: error, onRetry: onRetry),
        data: (resolved) {
          if (empty != null && resolved is Iterable && resolved.isEmpty) {
            return empty!();
          }
          return data(resolved);
        },
      );
}

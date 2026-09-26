import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/outbox_message.dart';
import '../../data/models/resort_membership.dart';
import '../../data/repositories/outbox_repository.dart';
import 'delivery_status_panel.dart';
import 'providers.dart';

final _timestamp = DateFormat('d MMM yyyy, HH:mm');
final _clockTime = DateFormat('HH:mm');

IconData _channelIcon(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => Icons.mail_outline,
      OutboxChannel.sms => Icons.sms_outlined,
      OutboxChannel.whatsapp => Icons.chat_outlined,
    };

String outboxStatusLabel(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => 'Pending',
      OutboxStatus.sent => 'Sent',
      OutboxStatus.failed => 'Failed',
      OutboxStatus.skipped => 'Skipped',
      OutboxStatus.dryRun => 'Dry run',
    };

/// Section order: what is still on its way, what did not go out, then what
/// did.
const outboxStatusOrder = [
  OutboxStatus.pending,
  OutboxStatus.failed,
  OutboxStatus.dryRun,
  OutboxStatus.skipped,
  OutboxStatus.sent,
];

/// The one extra line under a row's channel and template, or null. A row
/// on its first attempt (no error yet) has none.
String? attemptLine(OutboxMessage m) => switch (m.status) {
      OutboxStatus.pending
          when m.attempts > 0 && m.lastError != null && m.nextAttemptAt != null =>
        'Attempt ${m.attempts} of $outboxMaxAttempts failed · next try '
            '${_clockTime.format(m.nextAttemptAt!.toLocal())}',
      // Retired by 0056 before any attempt: queued before delivery existed.
      OutboxStatus.failed when m.attempts == 0 => 'Not sent',
      OutboxStatus.failed =>
        'Failed after ${m.attempts} attempt${m.attempts == 1 ? '' : 's'}',
      OutboxStatus.sent when m.sentAt != null =>
        'Sent ${_timestamp.format(m.sentAt!.toLocal())}',
      _ => null,
    };

/// Only a failed or dry-run message can be sent again
/// (`retry_outbox_message`, P0037 otherwise).
bool canSendAgain(OutboxMessage m) =>
    m.status == OutboxStatus.failed || m.status == OutboxStatus.dryRun;

/// `/admin/outbox` -- every guest notification for the current resort,
/// grouped by status, under a panel that says how each channel is being
/// delivered and when the sender last ran. Reachable by staff and above
/// (RLS `outbox_read` underneath); Send again is for owners and admins,
/// which `retry_outbox_message` enforces too.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key, this.clock});

  /// Injected so tests can pin "now" for the panel's "last checked" line;
  /// null means the real clock.
  final DateTime Function()? clock;

  Future<void> _sendAgain(
    BuildContext context,
    WidgetRef ref,
    String propertyId,
    OutboxMessage message,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(outboxSourceProvider).retry(message.id);
      ref.invalidate(outboxMessagesProvider(propertyId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Queued to send again.')),
      );
    } on BookingFailure catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(FailureView.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resort = ref.watch(currentResortProvider)!;
    final propertyId = resort.propertyId;
    final canRetry =
        const {ResortRole.owner, ResortRole.admin}.contains(resort.role);
    final messagesAsync = ref.watch(outboxMessagesProvider(propertyId));
    final statusAsync = ref.watch(outboxDeliveryStatusProvider(propertyId));

    void refresh() {
      ref.invalidate(outboxDeliveryStatusProvider(propertyId));
      ref.invalidate(outboxMessagesProvider(propertyId));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Outbox'),
        actions: [
          IconButton(
            key: const Key('outbox-refresh'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: refresh,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeliveryStatusPanel(status: statusAsync, now: (clock ?? DateTime.now)()),
          Expanded(
            child: AsyncView(
              value: messagesAsync,
              onRetry: () => ref.invalidate(outboxMessagesProvider(propertyId)),
              empty: () => const EmptyState(
                icon: Icons.mail_outline,
                title: 'Nothing queued yet',
                message:
                    'Messages appear here as bookings are confirmed or '
                    'cancelled.',
              ),
              data: (messages) => RefreshIndicator(
                onRefresh: () async => refresh(),
                child: _GroupedList(
                  messages: messages,
                  onSendAgain: canRetry
                      ? (m) => _sendAgain(context, ref, propertyId, m)
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.messages, required this.onSendAgain});

  final List<OutboxMessage> messages;

  /// Null when the viewer may not send messages again.
  final void Function(OutboxMessage message)? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final groups = <OutboxStatus, List<OutboxMessage>>{};
    for (final message in messages) {
      groups.putIfAbsent(message.status, () => []).add(message);
    }
    final sections = [
      for (final status in outboxStatusOrder)
        if (groups[status]?.isNotEmpty ?? false) status,
    ];
    final send = onSendAgain;

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final status = sections[i];
        final rows = groups[status]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: '${outboxStatusLabel(status)} (${rows.length})'),
            for (final message in rows)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: _OutboxTile(
                  message: message,
                  onSendAgain: send != null && canSendAgain(message)
                      ? () => send(message)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.message, required this.onSendAgain});

  final OutboxMessage message;
  final VoidCallback? onSendAgain;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extra = attemptLine(message);
    // A dry run is expected until keys are set -- not an error to alarm on.
    final errorColor = message.status == OutboxStatus.dryRun
        ? scheme.onSurfaceVariant
        : scheme.error;

    return Card(
      key: Key('outbox-row-${message.id}'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_channelIcon(message.channel), color: scheme.onSurfaceVariant),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.recipient, style: textTheme.bodyLarge),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    '${channelLabel(message.channel)} · ${message.template}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (extra != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(extra, style: textTheme.bodySmall),
                  ],
                  if (message.lastError != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      message.lastError!,
                      style: textTheme.bodySmall?.copyWith(color: errorColor),
                    ),
                  ],
                  if (onSendAgain != null) ...[
                    const SizedBox(height: Spacing.xs),
                    TextButton.icon(
                      key: Key('outbox-send-again-${message.id}'),
                      onPressed: onSendAgain,
                      icon: const Icon(Icons.replay),
                      label: const Text('Send again'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              _timestamp.format(message.createdAt.toLocal()),
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

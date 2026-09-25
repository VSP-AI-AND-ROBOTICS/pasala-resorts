import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/outbox_message.dart';
import 'providers.dart';

final _timestamp = DateFormat('d MMM yyyy, HH:mm');

String _channelLabel(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => 'Email',
      OutboxChannel.sms => 'SMS',
      OutboxChannel.whatsapp => 'WhatsApp',
    };

IconData _channelIcon(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => Icons.mail_outline,
      OutboxChannel.sms => Icons.sms_outlined,
      OutboxChannel.whatsapp => Icons.chat_outlined,
    };

String _statusLabel(OutboxStatus status) => switch (status) {
      OutboxStatus.pending => 'Pending',
      OutboxStatus.sent => 'Sent',
      OutboxStatus.failed => 'Failed',
      OutboxStatus.skipped => 'Skipped',
      OutboxStatus.dryRun => 'Dry run',
    };

/// The order sections appear in (Task 9 of the P7 plan rewrites this
/// screen around the delivery status panel).
const _statusOrder = [
  OutboxStatus.pending,
  OutboxStatus.failed,
  OutboxStatus.dryRun,
  OutboxStatus.skipped,
  OutboxStatus.sent,
];

/// `/admin/outbox` -- every queued (or skipped) notification, grouped by
/// status. Reachable by staff-or-above; RLS (`outbox_read`) is the real
/// enforcement underneath.
///
/// The banner up top is not a status message that happens to be showing
/// right now -- it is a permanent, structural fact about this phase of the
/// product: there is no email/SMS/WhatsApp provider wired up, so nothing
/// on this screen was ever delivered. It has no close button and is not
/// gated behind any provider/flag, so no future configuration change can
/// make it silently disappear -- the day a real sender ships, this banner
/// is deleted in the same change, not hidden by a setting.
class OutboxScreen extends ConsumerWidget {
  const OutboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final messagesAsync = ref.watch(outboxMessagesProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Outbox')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _NoProviderBanner(),
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
              data: (messages) => _GroupedList(messages: messages),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deliberately a plain, parameterless [StatelessWidget]: there is no
/// property on it that could suppress or reword this banner, so it cannot
/// be configured away -- see the class doc on [OutboxScreen].
class _NoProviderBanner extends StatelessWidget {
  const _NoProviderBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('no-provider-banner'),
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'No delivery provider is configured. Messages are queued but '
              'not sent.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.messages});

  final List<OutboxMessage> messages;

  @override
  Widget build(BuildContext context) {
    final groups = <OutboxStatus, List<OutboxMessage>>{};
    for (final message in messages) {
      groups.putIfAbsent(message.status, () => []).add(message);
    }
    final sections = [
      for (final status in _statusOrder)
        if (groups[status]?.isNotEmpty ?? false) status,
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Spacing.lg),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final status = sections[i];
        final rows = groups[status]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: '${_statusLabel(status)} (${rows.length})'),
            for (final message in rows)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                child: _OutboxTile(message: message),
              ),
          ],
        );
      },
    );
  }
}

class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.message});

  final OutboxMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
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
                    '${_channelLabel(message.channel)} · ${message.template}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (message.lastError != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      message.lastError!,
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
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

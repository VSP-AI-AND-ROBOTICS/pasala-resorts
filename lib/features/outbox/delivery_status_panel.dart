import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/channel_delivery.dart';
import '../../data/models/outbox_message.dart';

/// After this long without a run, the panel warns that the sender stopped
/// (pg_cron calls it every minute).
const staleAfter = Duration(minutes: 10);

String channelLabel(OutboxChannel channel) => switch (channel) {
      OutboxChannel.email => 'Email',
      OutboxChannel.sms => 'SMS',
      OutboxChannel.whatsapp => 'WhatsApp',
    };

String providerLabel(String? provider) => switch (provider) {
      'resend' => 'Resend',
      'msg91' => 'MSG91',
      final String p when p.isNotEmpty => p,
      _ => 'the provider',
    };

String deliveryLine(ChannelDelivery d) {
  final channel = channelLabel(d.channel);
  return switch (d.mode) {
    DeliveryMode.live => '$channel: sending via ${providerLabel(d.provider)}',
    DeliveryMode.dryRun => '$channel: dry run, nothing is sent',
    DeliveryMode.unavailable => '$channel: not connected, messages stay queued',
    DeliveryMode.notRunning => '$channel: waiting for the sender to run',
  };
}

DateTime? lastRunOf(List<ChannelDelivery> rows) {
  DateTime? latest;
  for (final row in rows) {
    final at = row.lastRunAt;
    if (at != null && (latest == null || at.isAfter(latest))) latest = at;
  }
  return latest;
}

String sinceLabel(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inDays < 1) return '${diff.inHours} h ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

bool senderLooksStopped(DateTime? lastRun, DateTime now) =>
    lastRun == null || now.difference(lastRun) > staleAfter;

String runLine(DateTime? lastRun, DateTime now) {
  if (lastRun == null) {
    return 'The sender has not run yet. Pending messages wait until it does.';
  }
  final since = sinceLabel(lastRun, now);
  if (senderLooksStopped(lastRun, now)) {
    return 'The sender last ran $since. Pending messages are waiting.';
  }
  return 'Last checked $since.';
}

IconData _modeIcon(DeliveryMode mode) => switch (mode) {
      DeliveryMode.live => Icons.check_circle_outline,
      DeliveryMode.dryRun => Icons.science_outlined,
      DeliveryMode.unavailable => Icons.block,
      DeliveryMode.notRunning => Icons.hourglass_empty,
    };

/// The top of the Outbox screen: how each channel is being delivered
/// (`outbox_delivery_status`) and when the sender last ran. Replaces the
/// old permanent "no provider" banner. States are shown with an icon and
/// words, never by colour alone.
class DeliveryStatusPanel extends StatelessWidget {
  const DeliveryStatusPanel({super.key, required this.status, required this.now});

  final AsyncValue<List<ChannelDelivery>> status;

  /// Injected so "3 min ago" is testable.
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      key: const Key('delivery-status-panel'),
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: status.when(
        loading: () => const LinearProgressIndicator(minHeight: 2),
        error: (_, _) => _PanelLine(
          icon: Icons.cloud_off_outlined,
          text: 'Delivery status is unavailable right now.',
          color: scheme.onSurfaceVariant,
        ),
        data: (rows) {
          final lastRun = lastRunOf(rows);
          final stopped = senderLooksStopped(lastRun, now);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows) ...[
                _PanelLine(
                  icon: _modeIcon(row.mode),
                  text: deliveryLine(row),
                  color: scheme.onSurface,
                ),
                if (row.mode == DeliveryMode.dryRun && row.detail != null)
                  Padding(
                    padding: const EdgeInsets.only(left: Spacing.xl),
                    child: Text(
                      row.detail!,
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
              _PanelLine(
                key: const Key('delivery-run-line'),
                icon: stopped ? Icons.warning_amber_outlined : Icons.schedule,
                text: runLine(lastRun, now),
                color: stopped ? scheme.error : scheme.onSurfaceVariant,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PanelLine extends StatelessWidget {
  const _PanelLine({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs / 2),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
}

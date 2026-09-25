import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/notification_settings.dart';
import '../../data/repositories/notification_settings_repository.dart';

/// Notification settings -- per-channel enable/disable toggles
/// (`0028_notification_settings.sql`). Every channel defaults to enabled.
/// Turning one off skips that channel's messages, both when they are
/// queued (`enqueue_outbox_message`) and when the sender claims them
/// (`claim_outbox_batch`, 0056), so messages already queued are not sent
/// either.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key, required this.propertyId});

  final String propertyId;

  /// Awaits the write, then invalidates to refetch -- no optimistic
  /// patching, matching `UsersScreen`'s own choice for the same reason (see
  /// its comment on why a mutation always re-reads the server's actual
  /// state rather than assuming the write succeeded as sent).
  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings updated,
  ) async {
    try {
      await ref.read(notificationSettingsRepositoryProvider).upsert(updated);
      ref.invalidate(notificationSettingsProvider(propertyId));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: AsyncView(
        value: settings,
        onRetry: () => ref.invalidate(notificationSettingsProvider(propertyId)),
        data: (s) => ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(Spacing.md),
                child: Text(
                  'Turn a channel off to stop sending it for this resort. '
                  'Messages already queued for that channel are skipped too. '
                  'The Outbox shows what was sent.',
                ),
              ),
            ),
            const SizedBox(height: Spacing.md),
            SwitchListTile(
              key: const Key('notification-email-switch'),
              title: const Text('Email'),
              value: s.emailEnabled,
              onChanged: (value) => _toggle(
                context,
                ref,
                NotificationSettings(
                  propertyId: s.propertyId,
                  emailEnabled: value,
                  smsEnabled: s.smsEnabled,
                  whatsappEnabled: s.whatsappEnabled,
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('notification-sms-switch'),
              title: const Text('SMS'),
              value: s.smsEnabled,
              onChanged: (value) => _toggle(
                context,
                ref,
                NotificationSettings(
                  propertyId: s.propertyId,
                  emailEnabled: s.emailEnabled,
                  smsEnabled: value,
                  whatsappEnabled: s.whatsappEnabled,
                ),
              ),
            ),
            SwitchListTile(
              key: const Key('notification-whatsapp-switch'),
              title: const Text('WhatsApp'),
              value: s.whatsappEnabled,
              onChanged: (value) => _toggle(
                context,
                ref,
                NotificationSettings(
                  propertyId: s.propertyId,
                  emailEnabled: s.emailEnabled,
                  smsEnabled: s.smsEnabled,
                  whatsappEnabled: value,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

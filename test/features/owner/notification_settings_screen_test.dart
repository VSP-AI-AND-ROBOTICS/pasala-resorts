import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/notification_settings.dart';
import 'package:pasala/data/repositories/notification_settings_repository.dart';
import 'package:pasala/features/owner/notification_settings_screen.dart';

class FakeNotificationSettingsRepository
    implements NotificationSettingsRepository {
  NotificationSettings current = const NotificationSettings(
    propertyId: 'p1',
    emailEnabled: true,
    smsEnabled: true,
    whatsappEnabled: true,
  );
  final List<NotificationSettings> saved = [];

  @override
  Future<NotificationSettings> get(String propertyId) async => current;

  @override
  Future<void> upsert(NotificationSettings settings) async {
    saved.add(settings);
    current = settings;
  }
}

Widget _appFor(FakeNotificationSettingsRepository repo) => ProviderScope(
      overrides: [
        notificationSettingsRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(
        home: NotificationSettingsScreen(propertyId: 'p1'),
      ),
    );

void main() {
  testWidgets('shows every channel switch, all on by default', (tester) async {
    await tester.pumpWidget(_appFor(FakeNotificationSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);

    final smsSwitch = tester.widget<SwitchListTile>(
      find.byKey(const Key('notification-sms-switch')),
    );
    expect(smsSwitch.value, isTrue);
  });

  testWidgets('turning off sms saves the change', (tester) async {
    final repo = FakeNotificationSettingsRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-sms-switch')));
    await tester.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.smsEnabled, isFalse);
    expect(repo.saved.single.emailEnabled, isTrue);
  });

  testWidgets('explains what a switch does, without claiming nothing sends',
      (tester) async {
    await tester.pumpWidget(_appFor(FakeNotificationSettingsRepository()));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Turn a channel off to stop sending it for this resort. Messages '
        'already queued for that channel are skipped too. The Outbox shows '
        'what was sent.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('nothing sends'), findsNothing);
  });
}

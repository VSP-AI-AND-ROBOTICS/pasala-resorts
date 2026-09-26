import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/notification_settings.dart';

class NotificationSettingsRepository {
  NotificationSettingsRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// Every property is backfilled a row by `0028_notification_settings.sql`,
  /// but a property created afterwards may not have one yet -- `maybeSingle`
  /// returns `null` rather than throwing, and the caller falls back to the
  /// same all-enabled default the database itself uses when no row exists.
  Future<NotificationSettings> get(String propertyId) => _guard(() async {
        final row = await _db
            .from('notification_settings')
            .select()
            .eq('property_id', propertyId)
            .maybeSingle();
        return row == null
            ? NotificationSettings(
                propertyId: propertyId,
                emailEnabled: true,
                smsEnabled: true,
                whatsappEnabled: true,
              )
            : NotificationSettings.fromJson(row);
      });

  Future<void> upsert(NotificationSettings settings) => _guard(() async {
        await _db.from('notification_settings').upsert({
          'property_id': settings.propertyId,
          ...settings.toUpdate(),
        });
      });
}

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>(
  (ref) => NotificationSettingsRepository(ref.watch(supabaseProvider)),
);

final notificationSettingsProvider =
    FutureProvider.family<NotificationSettings, String>(
  (ref, propertyId) =>
      ref.watch(notificationSettingsRepositoryProvider).get(propertyId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

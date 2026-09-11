/// One row of `notification_settings` -- whether each outbox channel is
/// enabled for a property. Purely a routing toggle: nothing here implies
/// any channel actually sends anything yet (see `outbox_screen.dart`'s
/// permanent banner).
class NotificationSettings {
  const NotificationSettings({
    required this.propertyId,
    required this.emailEnabled,
    required this.smsEnabled,
    required this.whatsappEnabled,
  });

  final String propertyId;
  final bool emailEnabled;
  final bool smsEnabled;
  final bool whatsappEnabled;

  factory NotificationSettings.fromJson(Map<String, dynamic> json) =>
      NotificationSettings(
        propertyId: json['property_id'] as String,
        emailEnabled: json['email_enabled'] as bool? ?? true,
        smsEnabled: json['sms_enabled'] as bool? ?? false,
        whatsappEnabled: json['whatsapp_enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toUpdate() => {
        'email_enabled': emailEnabled,
        'sms_enabled': smsEnabled,
        'whatsapp_enabled': whatsappEnabled,
      };
}

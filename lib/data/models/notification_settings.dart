/// One row of `notification_settings` -- whether each outbox channel is
/// used for a property. A channel that is off is skipped both when a
/// message is queued and when the sender claims it (0056).
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

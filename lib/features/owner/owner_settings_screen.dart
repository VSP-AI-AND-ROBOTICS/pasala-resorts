import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../admin/property_form_screen.dart';
import '../admin/units_screen.dart';
import '../browse/providers.dart';
import 'booking_rules_screen.dart';
import 'cancellation_policy_screen.dart';
import 'notification_settings_screen.dart';
import 'payment_settings_screen.dart';
import 'tax_settings_screen.dart';

/// `/owner/settings` -- the hub for every owner-level control: some open a
/// screen built for this flow (tax, payment display, cancellation policy,
/// booking rules, notifications); others push an EXISTING admin screen
/// unchanged (Farmhouse Information -> `PropertyFormScreen`, Pricing ->
/// `UnitsScreen` -> `RateRulesScreen`, Staff permissions -> `UsersScreen`)
/// so nothing here duplicates a working screen.
class OwnerSettingsScreen extends ConsumerWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView(
        value: properties,
        onRetry: () => ref.invalidate(propertiesProvider),
        data: (list) {
          final property = list.isEmpty ? null : list.first;
          final scheme = Theme.of(context).colorScheme;
          final textTheme = Theme.of(context).textTheme;

          Widget eyebrow(String text) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Text(text,
                    style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant, letterSpacing: 0.5)),
              );

          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              eyebrow('PROPERTY'),
              _SettingsTile(
                icon: Icons.home_work_outlined,
                title: 'Farmhouse information',
                subtitle: 'Name, description, address, amenities, check-in/out',
                color: scheme.primary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PropertyFormScreen(existing: property),
                        )),
              ),
              _SettingsTile(
                icon: Icons.sell_outlined,
                title: 'Pricing',
                subtitle: 'Rate rules per unit',
                color: scheme.primary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => UnitsScreen(propertyId: property.id),
                        )),
              ),
              _SettingsTile(
                icon: Icons.percent_outlined,
                title: 'Taxes',
                subtitle: 'Tax rate and GSTIN',
                color: scheme.primary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TaxSettingsScreen(property: property),
                        )),
              ),
              _SettingsTile(
                icon: Icons.payments_outlined,
                title: 'Payment configuration',
                subtitle: 'Advance %, accepted methods shown to customers',
                color: scheme.primary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => PaymentSettingsScreen(property: property),
                        )),
              ),
              const SizedBox(height: Spacing.md),
              eyebrow('POLICIES'),
              _SettingsTile(
                icon: Icons.policy_outlined,
                title: 'Cancellation policy',
                subtitle: 'Refund percentage by days before check-in',
                color: scheme.tertiary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CancellationPolicyScreen(property: property),
                        )),
              ),
              _SettingsTile(
                icon: Icons.rule_outlined,
                title: 'Booking rules',
                subtitle: 'Minimum and maximum stay length',
                color: scheme.tertiary,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => BookingRulesScreen(property: property),
                        )),
              ),
              const SizedBox(height: Spacing.md),
              eyebrow('TEAM & NOTIFICATIONS'),
              _SettingsTile(
                icon: Icons.people_outline,
                title: 'Staff permissions',
                subtitle: 'Roster and role assignment',
                color: scheme.onSurfaceVariant,
                onTap: () => context.push('/admin/users'),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notification settings',
                subtitle: 'Enable or disable email, SMS, and WhatsApp',
                color: scheme.onSurfaceVariant,
                onTap: property == null
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              NotificationSettingsScreen(propertyId: property.id),
                        )),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: Spacing.sm),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

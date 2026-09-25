import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/subscription_repository.dart';
import '../admin/property_form_screen.dart';
import '../admin/units_screen.dart';
import '../browse/providers.dart';
import 'booking_rules_screen.dart';
import 'cancellation_policy_screen.dart';
import 'notification_settings_screen.dart';
import 'payment_settings_screen.dart';
import 'property_photos_screen.dart';
import 'tax_settings_screen.dart';

/// `/owner/settings` -- the hub for every owner-level control: some open a
/// screen built for this flow (tax, payment display, cancellation policy,
/// booking rules, notifications); others push an EXISTING admin screen
/// unchanged (Farmhouse Information -> `PropertyFormScreen`, Pricing ->
/// `UnitsScreen` -> `RateRulesScreen`) so nothing here duplicates a
/// working screen. Staff permissions -> `UsersScreen` was removed in Task
/// 14 along with the global `UserRole` it managed; the Team screen
/// replacing it lands in Task 18. The Plan tile at the top shows the
/// resort's ResortHub plan, read-only.
class OwnerSettingsScreen extends ConsumerWidget {
  const OwnerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final property = ref.watch(propertyProvider(propertyId));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AsyncView(
        value: property,
        onRetry: () => ref.invalidate(propertyProvider(propertyId)),
        data: (property) {
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
              eyebrow('PLAN'),
              _PlanTile(propertyId: propertyId),
              const SizedBox(height: Spacing.md),
              eyebrow('PROPERTY'),
              _SettingsTile(
                icon: Icons.home_work_outlined,
                title: 'Farmhouse information',
                subtitle: 'Name, description, address, amenities, check-in/out',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyFormScreen(existing: property),
                )),
              ),
              _SettingsTile(
                icon: Icons.photo_library_outlined,
                title: 'Photos',
                subtitle: 'Pictures guests see on your listing',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PropertyPhotosScreen(propertyId: property.id),
                )),
              ),
              _SettingsTile(
                icon: Icons.sell_outlined,
                title: 'Pricing',
                subtitle: 'Rate rules per unit',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UnitsScreen(propertyId: property.id),
                )),
              ),
              _SettingsTile(
                icon: Icons.percent_outlined,
                title: 'Taxes',
                subtitle: 'Tax rate and GSTIN',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TaxSettingsScreen(property: property),
                )),
              ),
              _SettingsTile(
                icon: Icons.payments_outlined,
                title: 'Payment configuration',
                subtitle: 'Advance %, accepted methods shown to customers',
                color: scheme.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
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
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CancellationPolicyScreen(property: property),
                )),
              ),
              _SettingsTile(
                icon: Icons.rule_outlined,
                title: 'Booking rules',
                subtitle: 'Minimum and maximum stay length',
                color: scheme.tertiary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BookingRulesScreen(property: property),
                )),
              ),
              const SizedBox(height: Spacing.md),
              eyebrow('TEAM & NOTIFICATIONS'),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notification settings',
                subtitle: 'Enable or disable email, SMS, and WhatsApp',
                color: scheme.onSurfaceVariant,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NotificationSettingsScreen(propertyId: property.id),
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

/// The resort's ResortHub plan, read-only (spec decision 8): only the
/// platform admin changes it. Watches its own provider, so a failure here
/// never hides the rest of Settings.
class _PlanTile extends ConsumerWidget {
  const _PlanTile({required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final (title, subtitle, lapsed) =
        switch (ref.watch(resortPlanProvider(propertyId))) {
      AsyncData(value: final plan?) =>
        ('Plan: ${plan.name}', planStatusLine(plan), plan.lapsed),
      AsyncData() =>
        ('Plan: not set up', 'Contact ResortHub to choose a plan', false),
      AsyncError() => ('Plan', 'Could not load your plan', false),
      _ => ('Plan', 'Loading…', false),
    };

    return Card(
      key: const Key('owner-plan-tile'),
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.secondary.withValues(alpha: 0.12),
          child: Icon(Icons.workspace_premium_outlined, color: scheme.secondary),
        ),
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: lapsed ? TextStyle(color: scheme.error) : null,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/platform_repository.dart';

/// The console's live search and tier filter (REQ-08), applied on the
/// device over `platform_resorts()`, which is fine at tens or hundreds of
/// resorts. [query] matches the resort name or any owner email, ignoring
/// case and surrounding spaces. A [tier] hides resorts on other tiers and
/// resorts with no plan; null ("All Tiers") keeps them all. Order is kept.
List<ResortSummary> filterResorts(
  List<ResortSummary> resorts, {
  String query = '',
  SubscriptionTier? tier,
}) {
  final q = query.trim().toLowerCase();
  bool matches(ResortSummary r) =>
      q.isEmpty ||
      r.name.toLowerCase().contains(q) ||
      r.ownerEmails.any((e) => e.toLowerCase().contains(q));
  return [
    for (final r in resorts)
      if ((tier == null || r.plan?.tier == tier) && matches(r)) r,
  ];
}

/// The search field and the tier dropdown above the resort list.
class ResortFilterBar extends StatelessWidget {
  const ResortFilterBar({
    super.key,
    required this.search,
    required this.tier,
    required this.onSearchChanged,
    required this.onTierChanged,
  });

  final TextEditingController search;
  final SubscriptionTier? tier;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<SubscriptionTier?> onTierChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('resort-search'),
              controller: search,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search resorts or owner emails',
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
          DropdownButton<SubscriptionTier?>(
            key: const Key('tier-filter'),
            value: tier,
            onChanged: onTierChanged,
            items: [
              const DropdownMenuItem<SubscriptionTier?>(
                  value: null, child: Text('All Tiers')),
              for (final t in SubscriptionTier.values)
                DropdownMenuItem<SubscriptionTier?>(
                    value: t, child: Text(t.label)),
            ],
          ),
        ],
      );
}

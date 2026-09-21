import 'package:flutter/material.dart';
import '../../core/models/resort.dart';
import '../../core/models/subscription.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/widgets/resort_inspector_header.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final MockDataStore _store = MockDataStore.instance;

  void _updateResortTier(Resort resort, SubscriptionTier newTier) {
    setState(() {
      final updatedResort = resort.copyWith(subscriptionTier: newTier);
      _store.resorts[resort.id] = updatedResort;

      // Update corresponding subscription record
      if (_store.resortSubscriptions.containsKey(resort.id)) {
        final currentSub = _store.resortSubscriptions[resort.id]!;
        _store.resortSubscriptions[resort.id] = ResortSubscription(
          id: currentSub.id,
          resortId: resort.id,
          planId: 'plan-${newTier.dbValue}',
          tier: newTier,
          status: SubscriptionStatus.active,
          currentPeriodStart: DateTime.now(),
          currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
          cancelAtPeriodEnd: false,
        );
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated ${resort.name} subscription tier to ${newTier.badgeText}')),
    );
  }

  void _toggleSubscriptionStatus(String resortId, SubscriptionStatus newStatus) {
    setState(() {
      if (_store.resortSubscriptions.containsKey(resortId)) {
        final sub = _store.resortSubscriptions[resortId]!;
        _store.resortSubscriptions[resortId] = ResortSubscription(
          id: sub.id,
          resortId: sub.resortId,
          planId: sub.planId,
          tier: sub.tier,
          status: newStatus,
          currentPeriodStart: sub.currentPeriodStart,
          currentPeriodEnd: sub.currentPeriodEnd,
          cancelAtPeriodEnd: sub.cancelAtPeriodEnd,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Lifecycle Management'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          ResortInspectorHeader(onResortChanged: () => setState(() {})),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: Colors.teal.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info, color: Colors.teal),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Co-owner visibility: Manage Premium, Super, Basic, and Free plans. Modify resort subscription tiers and monitor status (Active, Trial, Suspended, Expired).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _store.resorts.length,
              itemBuilder: (context, index) {
                final resort = _store.resorts.values.elementAt(index);
                final sub = _store.resortSubscriptions[resort.id];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(resort.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('Current Tier: ${resort.subscriptionTier.badgeText} | Status: ${sub?.status.displayName ?? 'Active'}'),
                        if (sub != null)
                          Text('Renewal Date: ${sub.currentPeriodEnd.toString().split(' ')[0]}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButton<SubscriptionTier>(
                          value: resort.subscriptionTier,
                          items: SubscriptionTier.values.map((tier) {
                            return DropdownMenuItem(
                              value: tier,
                              child: Text(tier.badgeText),
                            );
                          }).toList(),
                          onChanged: (newTier) {
                            if (newTier != null) {
                              _updateResortTier(resort, newTier);
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<SubscriptionStatus>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (status) => _toggleSubscriptionStatus(resort.id, status),
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: SubscriptionStatus.active, child: Text('Set Active')),
                            const PopupMenuItem(value: SubscriptionStatus.trial, child: Text('Set Trial')),
                            const PopupMenuItem(value: SubscriptionStatus.suspended, child: Text('Set Suspended')),
                            const PopupMenuItem(value: SubscriptionStatus.expired, child: Text('Set Expired')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }
}

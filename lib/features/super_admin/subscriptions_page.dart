import 'package:flutter/material.dart';
import '../../core/models/resort.dart';
import '../../core/models/subscription.dart';
import '../../core/models/salary_disbursement.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/widgets/resort_inspector_header.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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

  void _openSendPaymentDetailsDialog(TierChangeRequest req) {
    final amountCtrl = TextEditingController(text: req.amountDue.toStringAsFixed(2));
    final defaultInstructions =
        'Beneficiary: ResortHub Technologies Pvt Ltd\n'
        'Bank: ICICI Bank Ltd\n'
        'Account Number: 009283748291\n'
        'IFSC Code: ICIC0000092\n'
        'UPI ID: resorthub.billing@icici\n'
        'Please transfer ₹${req.amountDue.toStringAsFixed(2)} and enter your UTR reference in your Resort Admin Portal.';
    final instructionsCtrl = TextEditingController(text: defaultInstructions);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.send_outlined, color: Colors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Send Payment Details: ${req.resortName}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width > 500 ? 460 : double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upgrade: ${req.currentTier.badgeText} ➔ ${req.requestedTier.badgeText}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount Due (₹) *',
                    prefixIcon: Icon(Icons.currency_rupee),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: instructionsCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Payment Instructions & Bank/UPI Details *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'These bank and UPI details will be sent directly to the Resort Admin. Once they complete the payment and enter the UTR, the tier will automatically update.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton.icon(
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Dispatch Payment Details to Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  final amt = double.tryParse(amountCtrl.text.trim()) ?? req.amountDue;
                  final instructions = instructionsCtrl.text.trim();
                  if (instructions.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment instructions cannot be empty.')),
                    );
                    return;
                  }

                  _store.sendTierPaymentDetails(
                    requestId: req.id,
                    paymentInstructions: instructions,
                    customAmount: amt,
                  );

                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment details dispatched to ${req.resortName} Admin.'),
                      backgroundColor: Colors.teal.shade800,
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = _store.tierChangeRequests.where((r) => r.status == TierRequestStatus.pendingPaymentDetails).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Lifecycle Management'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFEBB02),
          indicatorWeight: 3,
          labelColor: const Color(0xFFFEBB02),
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: [
            Tab(
              icon: const Icon(Icons.business_center_outlined),
              text: 'Resort Subscriptions (${_store.resorts.length})',
            ),
            Tab(
              icon: Badge(
                isLabelVisible: pendingRequests > 0,
                label: Text('$pendingRequests'),
                backgroundColor: Colors.amber.shade900,
                child: const Icon(Icons.upgrade_outlined),
              ),
              text: 'Tier Upgrade Requests (${_store.tierChangeRequests.length})',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          ResortInspectorHeader(onResortChanged: () => setState(() {})),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildResortsListTab(),
                _buildTierRequestsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildResortsListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            color: Colors.teal.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
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
    );
  }

  Widget _buildTierRequestsTab() {
    final requests = _store.tierChangeRequests;

    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 54, color: Colors.teal.shade300),
            const SizedBox(height: 12),
            const Text(
              'No Tier Upgrade Requests',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'When Resort Admins request a plan upgrade, their requests appear here.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];

        Color statusColor = Colors.amber.shade800;
        Color statusBg = Colors.amber.shade100;
        String statusLabel = 'Action Needed: Send Payment Details';

        if (req.status == TierRequestStatus.awaitingAdminPayment) {
          statusColor = Colors.blue.shade800;
          statusBg = Colors.blue.shade100;
          statusLabel = 'Payment Details Sent - Waiting for Admin UTR';
        } else if (req.status == TierRequestStatus.completed) {
          statusColor = Colors.green.shade800;
          statusBg = Colors.green.shade100;
          statusLabel = 'Completed & Upgraded';
        } else if (req.status == TierRequestStatus.rejected) {
          statusColor = Colors.red.shade800;
          statusBg = Colors.red.shade100;
          statusLabel = 'Rejected';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Resort Name on its own row for full readability
                Text(
                  req.resortName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                // 2. Status Badge with full wrap and clean padding
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 12),
                // 3. Current Tier -> Requested Tier & Amount in responsive Wrap
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                          child: Text('Current: ${req.currentTier.badgeText}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(Icons.arrow_forward, size: 14, color: Colors.teal),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.teal.shade100, borderRadius: BorderRadius.circular(6)),
                          child: Text('Requested: ${req.requestedTier.badgeText}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        'Amount: ₹${req.amountDue.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.green.shade900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Requested: ${req.createdAt.toString().split(' ')[0]} at ${req.createdAt.toString().split(' ')[1].substring(0, 5)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                if (req.paymentInstructions != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Payment Instructions Sent:',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        const SizedBox(height: 4),
                        SelectableText(req.paymentInstructions!,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.35)),
                      ],
                    ),
                  ),
                ],
                if (req.adminPaymentRef != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    children: [
                      const Icon(Icons.receipt_long, color: Colors.green, size: 16),
                      const Text('Admin Payment UTR / Ref: ',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      SelectableText(req.adminPaymentRef!,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green, fontFamily: 'monospace')),
                    ],
                  ),
                ],
                const Divider(height: 24),
                // Actions (Full width button on mobile for optimal tap targets)
                SizedBox(
                  width: double.infinity,
                  child: req.status == TierRequestStatus.pendingPaymentDetails
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.send_outlined, size: 16),
                          label: const Text('Send Payment Details to Admin'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openSendPaymentDetailsDialog(req),
                        )
                      : req.status == TierRequestStatus.awaitingAdminPayment
                          ? OutlinedButton.icon(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: const Text('Update Payment Instructions'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.teal.shade800,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _openSendPaymentDetailsDialog(req),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green, size: 18),
                                SizedBox(width: 6),
                                Text('Tier Upgraded & Active',
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}


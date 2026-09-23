import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/resort.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';

class PromotionalMessagingDialog extends StatefulWidget {
  final Resort resort;

  const PromotionalMessagingDialog({
    super.key,
    required this.resort,
  });

  @override
  State<PromotionalMessagingDialog> createState() => _PromotionalMessagingDialogState();
}

class _PromotionalMessagingDialogState extends State<PromotionalMessagingDialog> {
  final MockDataStore _store = MockDataStore.instance;
  late final TextEditingController _offerTitleController;
  late final TextEditingController _offerBodyController;

  @override
  void initState() {
    super.initState();
    _offerTitleController = TextEditingController(text: '🌟 Special 25% Off Weekend Stay!');
    _offerBodyController = TextEditingController(
      text: 'Experience luxury at ${widget.resort.name} (${widget.resort.city}). Book now and enjoy free breakfast & spa access!',
    );
  }

  @override
  void dispose() {
    _offerTitleController.dispose();
    _offerBodyController.dispose();
    super.dispose();
  }

  void _sendBroadcastMessage(List<UserProfile> registeredCustomers) {
    if (_offerTitleController.text.trim().isEmpty) return;

    final title = _offerTitleController.text.trim();
    final body = _offerBodyController.text.trim();

    Navigator.pop(context); // Close compose modal

    // Show simulated customer SMS inbox card modal
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SMS Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.resortCharcoal,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.mark_email_read_outlined, color: Color(0xFFFEBB02), size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Promotional SMS Delivered!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('Broadcast sent to ${registeredCustomers.length} registered app customers', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Simulated Received SMS Message Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  border: Border.all(color: AppTheme.resortCoral.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sms, color: AppTheme.resortCoral, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'SMS FROM: ${widget.resort.name.toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.resortDarkText),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.resortDarkText)),
                    const SizedBox(height: 6),
                    Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.4)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFFE7E5E4))),
                      child: Row(
                        children: [
                          const Icon(Icons.link, color: AppTheme.resortCoral, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'resorthub://resort/${widget.resort.id}',
                              style: const TextStyle(fontSize: 11, color: AppTheme.resortCoral, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Deep Link Action Button
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(
                        'Open ${widget.resort.name} in App',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.resortCoral,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.go('/customer/resort/${widget.resort.id}');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close Preview'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final registeredCustomers = _store.profiles.values
        .where((u) => u.role == AppRole.customer)
        .toList();

    final isPremium = widget.resort.subscriptionTier == SubscriptionTier.premium ||
        widget.resort.subscriptionTier == SubscriptionTier.superTier;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            isPremium ? Icons.campaign_rounded : Icons.lock,
            color: isPremium ? const Color(0xFF0F172A) : Colors.amber.shade900,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Broadcast Promotional SMS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isPremium) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.workspace_premium, color: Colors.amber.shade900, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Promotional SMS is exclusive to Premium Subscribed Resorts. Please upgrade tier to broadcast offers.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Recipient Counter Tile
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people_alt_outlined, color: Color(0xFF0F172A), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target Audience: ${registeredCustomers.length} Registered Customer Accounts in App',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _offerTitleController,
              enabled: isPremium,
              decoration: const InputDecoration(
                labelText: 'Promotion Headline *',
                hintText: 'e.g. 25% Off Weekend Luxury Stay',
                prefixIcon: Icon(Icons.title),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _offerBodyController,
              enabled: isPremium,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message Body & Offer Details *',
                hintText: 'e.g. Book now to get complimentary breakfast & spa coupon...',
                prefixIcon: Icon(Icons.message),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.resortCoral.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.add_link, color: AppTheme.resortCoral, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('App Deep Link Included Automatically:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.resortDarkText)),
                        Text('resorthub://resort/${widget.resort.id}', style: const TextStyle(fontSize: 11, color: AppTheme.resortCoral)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton.icon(
          icon: const Icon(Icons.send_rounded, size: 18),
          label: const Text('Broadcast SMS'),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPremium ? AppTheme.resortCoral : Colors.grey,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: isPremium ? () => _sendBroadcastMessage(registeredCustomers) : null,
        ),
      ],
    );
  }
}

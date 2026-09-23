import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/resort.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import 'assign_admin_dialog.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class BrowseResortsPage extends StatefulWidget {
  const BrowseResortsPage({super.key});

  @override
  State<BrowseResortsPage> createState() => _BrowseResortsPageState();
}

class _BrowseResortsPageState extends State<BrowseResortsPage> {
  final MockDataStore _store = MockDataStore.instance;
  String _searchQuery = '';
  SubscriptionTier? _filterTier;

  @override
  void initState() {
    super.initState();
    // Reset selected resort inspection when viewing Super Admin Home Page
    _store.superAdminSelectedResortId = null;
  }

  void _openAssignAdminDialog(Resort resort) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AssignAdminDialog(resort: resort),
    );
    if (updated == true) {
      setState(() {});
    }
  }

  void _openAddResortDialog() {
    final nameCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final stateCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final imgCtrl = TextEditingController();
    SubscriptionTier selectedTier = SubscriptionTier.premium;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_business, color: AppTheme.bookingNavy),
              SizedBox(width: 10),
              Expanded(
                child: Text('Add New Resort', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17), overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 560 ? 520 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Resort Information', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.bookingNavy)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Resort Name *', hintText: 'e.g. Royal Palms Resort'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cityCtrl,
                          decoration: const InputDecoration(labelText: 'City *', hintText: 'e.g. Hyderabad'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: stateCtrl,
                          decoration: const InputDecoration(labelText: 'State *', hintText: 'e.g. Telangana'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: 'Street Address', hintText: 'e.g. Road No 36, Jubilee Hills'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Description', hintText: 'Luxury resort featuring private pools and fine dining.'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          decoration: const InputDecoration(labelText: 'Contact Email', hintText: 'info@resort.com'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(labelText: 'Contact Phone', hintText: '+91 98765 00000'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<SubscriptionTier>(
                    initialValue: selectedTier,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Subscription Tier'),
                    items: SubscriptionTier.values
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.badgeText)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedTier = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: imgCtrl,
                    decoration: const InputDecoration(labelText: 'Cover Image URL (Optional)', hintText: 'https://images.unsplash.com/...'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Add Resort'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.bookingActionBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || cityCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter Resort Name and City.')),
                  );
                  return;
                }

                final created = _store.addResort(
                  name: nameCtrl.text.trim(),
                  city: cityCtrl.text.trim(),
                  state: stateCtrl.text.trim().isEmpty ? 'Telangana' : stateCtrl.text.trim(),
                  address: addressCtrl.text.trim().isEmpty ? '100 Resort Way' : addressCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty ? 'Luxury 5-star resort with world-class amenities.' : descCtrl.text.trim(),
                  tier: selectedTier,
                  contactEmail: emailCtrl.text.trim().isEmpty ? 'contact@resorthub.com' : emailCtrl.text.trim(),
                  contactPhone: phoneCtrl.text.trim().isEmpty ? '+91 98765 00000' : phoneCtrl.text.trim(),
                  imageUrl: imgCtrl.text.trim(),
                );

                Navigator.of(ctx).pop();
                setState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Resort "${created.name}" created successfully! Click "Assign Admin" to assign a manager.'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteResort(Resort resort) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(child: Text('Delete ${resort.name}?')),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${resort.name}"?\n\nThis action will purge all associated room units, reservations, and admin accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_forever),
            label: const Text('Delete Resort'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _store.deleteResort(resort.id);
              Navigator.of(ctx).pop();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Resort "${resort.name}" removed from platform.'),
                  backgroundColor: Colors.red.shade700,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // When viewing the Super Admin Home Page, clear any active resort inspection selection
    _store.superAdminSelectedResortId = null;

    final allResorts = _store.resorts.values.toList();
    final resortsList = allResorts.where((r) {
      final matchesSearch = r.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.city.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesTier = _filterTier == null || r.subscriptionTier == _filterTier;
      return matchesSearch && matchesTier;
    }).toList();

    resortsList.sort((a, b) {
      final tierCompare = b.subscriptionTier.priorityOrder.compareTo(a.subscriptionTier.priorityOrder);
      if (tierCompare != 0) return tierCompare;
      return 0; // Maintains prepended insertion order (newest created first)
    });

    final totalActiveSubs = _store.resortSubscriptions.values.where((s) => s.status.name == 'active').length;
    final totalAdmins = _store.profiles.values.where((p) => p.role == AppRole.admin).length;

    final pageBg = AppTheme.pageBg(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        foregroundColor: textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A36).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield, color: Color(0xFFFF5A36), size: 20),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Co-owner Portal',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_business, color: AppTheme.bookingNavy),
            tooltip: 'Add Resort',
            onPressed: _openAddResortDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Admin Tools & Reports',
            onSelected: (val) {
              if (val == 'assign' && resortsList.isNotEmpty) {
                _openAssignAdminDialog(resortsList.first);
              } else if (val == 'subs') {
                context.go('/super-admin/subscriptions');
              } else if (val == 'pay') {
                context.go('/super-admin/payments');
              } else if (val == 'reports') {
                context.go('/super-admin/reports');
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'assign', child: Row(children: [Icon(Icons.person_add_alt_1, size: 18), SizedBox(width: 8), Text('Assign Admin')])),
              const PopupMenuItem(value: 'subs', child: Row(children: [Icon(Icons.subscriptions_outlined, size: 18), SizedBox(width: 8), Text('Subscriptions')])),
              const PopupMenuItem(value: 'pay', child: Row(children: [Icon(Icons.account_balance_wallet_outlined, size: 18), SizedBox(width: 8), Text('Payments')])),
              const PopupMenuItem(value: 'reports', child: Row(children: [Icon(Icons.bar_chart_outlined, size: 18), SizedBox(width: 8), Text('Reports')])),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: () {
              MockDataStore.instance.logout();
              context.go('/login');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Co-owner Executive Metrics Banner
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(width: 165, child: _buildHeaderMetric('Subscribed Resorts', '${allResorts.length}', Icons.holiday_village, Colors.teal)),
                  const SizedBox(width: 10),
                  SizedBox(width: 165, child: _buildHeaderMetric('Active Subscriptions', '$totalActiveSubs', Icons.verified_user, Colors.green)),
                  const SizedBox(width: 10),
                  SizedBox(width: 165, child: _buildHeaderMetric('Registered Admins', '$totalAdmins', Icons.admin_panel_settings, Colors.blue)),
                  const SizedBox(width: 10),
                  SizedBox(width: 165, child: _buildHeaderMetric('Monthly Revenue', '₹${_store.getSuperAdminTotalRevenue().toStringAsFixed(0)}', Icons.payments, Colors.amber)),
                ],
              ),
            ),
          ),
          const Divider(height: 1),

          // Search & Filter Controls
          // Search & Filter Controls (Mobile Friendly Column Layout)
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Search resorts by name, city...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<SubscriptionTier?>(
                            value: _filterTier,
                            isExpanded: true,
                            hint: const Text('Filter Tier', style: TextStyle(fontSize: 13)),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Tiers', style: TextStyle(fontSize: 13))),
                              ...SubscriptionTier.values.map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.badgeText, style: const TextStyle(fontSize: 13)),
                                  )),
                            ],
                            onChanged: (tier) => setState(() => _filterTier = tier),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Resort', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.bookingActionBlue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        onPressed: _openAddResortDialog,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: resortsList.isEmpty
                ? const Center(child: Text('No resorts match the search or filter criteria.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: resortsList.length,
                    itemBuilder: (context, index) {
                      final resort = resortsList[index];
                      final isInspected = _store.superAdminSelectedResortId == resort.id;
                      final assignedAdmin = _store.getAssignedAdminForResort(resort.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  Text(
                                    resort.name,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildTierBadge(resort.subscriptionTier),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: resort.status == 'active' ? Colors.green.shade50 : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: resort.status == 'active' ? Colors.green.shade300 : Colors.red.shade300,
                                          ),
                                        ),
                                        child: Text(
                                          resort.status.toUpperCase(),
                                          style: TextStyle(
                                            color: resort.status == 'active' ? Colors.green.shade900 : Colors.red.shade900,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.location_on_outlined, size: 16, color: Colors.blueGrey.shade400),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${resort.address}, ${resort.city}, ${resort.state}',
                                      style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(resort.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.4)),
                              const SizedBox(height: 12),
                              
                              // Assigned Admin Information Banner
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: assignedAdmin != null ? Colors.blue.shade50 : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: assignedAdmin != null ? Colors.blue.shade200 : Colors.amber.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      assignedAdmin != null ? Icons.badge_outlined : Icons.warning_amber_rounded,
                                      size: 18,
                                      color: assignedAdmin != null ? Colors.blue.shade900 : Colors.amber.shade900,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        assignedAdmin != null
                                            ? 'Manager: ${assignedAdmin.fullName} (${assignedAdmin.email})'
                                            : 'No Resort Manager assigned yet',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: assignedAdmin != null ? Colors.blue.shade900 : Colors.amber.shade900,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 20),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Contact: ${resort.contactEmail} | ${resort.contactPhone}',
                                    style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.start,
                                    children: [
                                      ElevatedButton.icon(
                                        icon: const Icon(Icons.person_add_outlined, size: 14),
                                        label: const Text('Assign Admin', style: TextStyle(fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primarySlate,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        ),
                                        onPressed: () => _openAssignAdminDialog(resort),
                                      ),
                                      ElevatedButton.icon(
                                        icon: Icon(isInspected ? Icons.check_circle : Icons.visibility_outlined, size: 14),
                                        label: Text(isInspected ? 'Inspecting' : 'Inspect', style: const TextStyle(fontSize: 11)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isInspected ? AppTheme.accentAmber : AppTheme.primaryTeal,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        ),
                                        onPressed: () {
                                          if (isInspected) {
                                            setState(() {
                                              _store.superAdminSelectedResortId = null;
                                            });
                                          } else {
                                            _store.superAdminSelectedResortId = resort.id;
                                            context.go('/super-admin/reports');
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        tooltip: 'Delete Resort',
                                        onPressed: () => _confirmDeleteResort(resort),
                                      ),
                                    ],
                                  ),
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

  Widget _buildHeaderMetric(String label, String val, IconData icon, MaterialColor color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color.shade800, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color.shade900)),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade500)),
          ],
        ),
      ],
    );
  }

  Widget _buildTierBadge(SubscriptionTier tier) {
    Color bg;
    Color fg;
    switch (tier) {
      case SubscriptionTier.premium:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade900;
        break;
      case SubscriptionTier.superTier:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade900;
        break;
      case SubscriptionTier.basic:
        bg = Colors.amber.shade50;
        fg = Colors.amber.shade900;
        break;
      case SubscriptionTier.free:
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade800;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Text(
        tier.badgeText,
        style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}

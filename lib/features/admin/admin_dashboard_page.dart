import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/staff.dart';
import '../../core/models/unit.dart';
import '../../core/models/salary_disbursement.dart';
import '../../core/models/user_profile.dart';
import '../../core/models/resort.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

import 'assign_incharge_dialog.dart';
import 'promotional_messaging_dialog.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final user = _store.currentUser;
    final resortId = user?.resortId ?? 'resort-grand-palms';
    final resort = _store.resorts[resortId];
    final report = _store.getDashboardReport(resortId);

    final isDark = AppTheme.isDark(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cardBg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border, width: 1)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5A36).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.business_center, color: Color(0xFFFF5A36), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Manager Portal: ${resort?.name ?? "My Resort"}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (resort != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.campaign, size: 16, color: Color(0xFF0F172A)),
                label: const Text('Promo SMS', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEBB02),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => PromotionalMessagingDialog(resort: resort),
                  );
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFE23744)),
            tooltip: 'Logout',
            onPressed: () {
              MockDataStore.instance.logout();
              context.go('/login');
            },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFFFF5A36),
          unselectedLabelColor: isDark ? AppTheme.resortDarkMuted : Colors.grey,
          indicatorColor: isDark ? AppTheme.resortMintPrimary : const Color(0xFFFF5A36),
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.book_online_outlined), text: 'Bookings'),
            Tab(icon: Icon(Icons.meeting_room_outlined), text: 'Units & Rates'),
            Tab(icon: Icon(Icons.badge_outlined), text: 'Incharge & Ops'),
            Tab(icon: Icon(Icons.attach_money_outlined), text: 'Resort Accounts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(resortId, report),
          _buildBookingsTab(resortId),
          _buildUnitsTab(resortId),
          _buildInchargeTab(resortId),
          _buildAccountsTab(resortId, report),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildOverviewTab(String resortId, report) {
    final resort = _store.resorts[resortId];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppTheme.resortCoral,
                    radius: 26,
                    child: const Icon(Icons.hotel_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(resort?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.resortDarkText)),
                        const SizedBox(height: 2),
                        Text('Tenant Scoped: ${resort?.city}, ${resort?.state}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.resortCoral.withOpacity(0.3)),
                          ),
                          child: Text(
                            'Subscription Tier: ${resort?.subscriptionTier.badgeText}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.resortCoral, fontSize: 11),
                          ),
                        ),
                        if (resort != null) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.badge_outlined, size: 16),
                            label: const Text('Assign / Change Incharge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.resortDarkText,
                              side: const BorderSide(color: Color(0xFFE7E5E4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AssignInchargeDialog(resort: resort),
                              ).then((updated) {
                                if (updated == true) {
                                  setState(() {});
                                }
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildTierSubscriptionCard(resortId, resort),
          const SizedBox(height: 24),
          const Text('Resort Operations Snapshot', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primarySlate)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Month Revenue', '₹${report.monthRevenue.toStringAsFixed(2)}', Icons.payments_outlined, Colors.green)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricTile('Occupancy Rate', '${report.occupancyRate}%', Icons.bed_outlined, Colors.blue)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildMetricTile('Upcoming Arrivals', '${report.upcomingArrivals}', Icons.flight_land_outlined, Colors.orange)),
              const SizedBox(width: 16),
              Expanded(child: _buildMetricTile('Net Profit', '₹${report.netProfit.toStringAsFixed(2)}', Icons.account_balance_outlined, Colors.teal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingsTab(String resortId) {
    final resList = _store.reservations.where((r) => r.resortId == resortId).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: resList.length,
      itemBuilder: (context, index) {
        final res = resList[index];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: Colors.teal.shade50,
              child: const Icon(Icons.person, color: AppTheme.primaryTeal),
            ),
            title: Text('${res.guestName} (${res.unitName ?? "Unit"})', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Dates: ${res.checkIn.toString().split(' ')[0]} to ${res.checkOut.toString().split(' ')[0]}\nAdvance Paid: ₹${res.advanceAmount} | Total Booking: ₹${res.totalAmount}',
                style: TextStyle(color: Colors.blueGrey.shade600, height: 1.4),
              ),
            ),
            trailing: Chip(
              label: Text(res.status.displayName),
              backgroundColor: Colors.blue.shade50,
              side: BorderSide(color: Colors.blue.shade200),
              labelStyle: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          ),
        );
      },
    );
  }

  void _openAddUnitDialog(String resortId) {
    final nameCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '2');
    final priceCtrl = TextEditingController(text: '250.00');
    final descCtrl = TextEditingController();
    String unitType = 'villa';
    String status = 'available';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.add_home_work, color: AppTheme.bookingNavy, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Add Resort Inventory Unit', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 520 ? 480 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create a new accommodation unit for guests to discover and reserve.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unit / Room Name *',
                      hintText: 'e.g. Royal Lakefront Villa 105',
                      prefixIcon: Icon(Icons.meeting_room, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unitType,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Unit Type'),
                          items: const [
                            DropdownMenuItem(value: 'villa', child: Text('Villa', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'suite', child: Text('Suite', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'cottage', child: Text('Cottage', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'deluxe', child: Text('Deluxe Room', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'penthouse', child: Text('Penthouse', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'chalet', child: Text('Chalet', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => unitType = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: status,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Status'),
                          items: const [
                            DropdownMenuItem(value: 'available', child: Text('Available', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'maintenance', child: Text('Maintenance', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'occupied', child: Text('Occupied', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => status = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capacityCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Guest Capacity *',
                            hintText: '2',
                            prefixIcon: Icon(Icons.people_outline, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Price / Night (₹) *',
                            hintText: '250.00',
                            prefixIcon: Icon(Icons.currency_rupee, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Unit Description & Amenities',
                      hintText: 'Private plunge pool, king bed, oceanview terrace, complimentary breakfast.',
                    ),
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
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Add Unit to Resort'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.bookingActionBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text.trim()) ?? 250.0;
                final capacity = int.tryParse(capacityCtrl.text.trim()) ?? 2;

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a Unit Name.')),
                  );
                  return;
                }

                final newUnit = ResortUnit(
                  id: 'unit-${DateTime.now().millisecondsSinceEpoch}',
                  resortId: resortId,
                  name: name,
                  type: unitType,
                  capacity: capacity,
                  pricePerNight: price,
                  description: descCtrl.text.trim().isEmpty ? 'Luxury $unitType with modern amenities.' : descCtrl.text.trim(),
                  status: status,
                  amenities: ['Wi-Fi', 'Air Conditioning', 'King Bed', 'Complimentary Breakfast', 'Balcony'],
                  imageUrls: ['https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800'],
                );

                final list = _store.resortUnits[resortId] ?? [];
                list.add(newUnit);
                _store.resortUnits[resortId] = list;

                Navigator.of(ctx).pop();
                setState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Unit "$name" added to resort inventory!'),
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

  void _openAddRateRuleDialog(String resortId) {
    final reasonCtrl = TextEditingController();
    String multiplierStr = '1.5';
    String durationDays = '7';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.purple.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.trending_up, color: Colors.purple, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Add Dynamic Surge Rate Rule', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 520 ? 480 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Set automated rate surge multipliers for peak seasons, holidays, or festival demands.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Surge Reason / Occasion *',
                      hintText: 'e.g. Diwali Festival Peak Surge',
                      prefixIcon: Icon(Icons.celebration, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: multiplierStr,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Price Multiplier'),
                          items: const [
                            DropdownMenuItem(value: '1.2', child: Text('1.2x (+20%)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '1.35', child: Text('1.35x (+35%)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '1.5', child: Text('1.5x (+50%)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '1.8', child: Text('1.8x (+80%)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '2.0', child: Text('2.0x (+100%)', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => multiplierStr = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: durationDays,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Period'),
                          items: const [
                            DropdownMenuItem(value: '7', child: Text('7 Days', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '14', child: Text('14 Days', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: '30', child: Text('30 Days', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => durationDays = val);
                          },
                        ),
                      ),
                    ],
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
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Activate Surge Rule'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a Surge Reason.')),
                  );
                  return;
                }

                final mult = double.tryParse(multiplierStr) ?? 1.5;
                final days = int.tryParse(durationDays) ?? 7;

                final newRule = RateRule(
                  id: 'rule-${DateTime.now().millisecondsSinceEpoch}',
                  resortId: resortId,
                  startDate: DateTime.now(),
                  endDate: DateTime.now().add(Duration(days: days)),
                  priceMultiplier: mult,
                  reason: reason,
                );

                final list = _store.resortRateRules[resortId] ?? [];
                list.add(newRule);
                _store.resortRateRules[resortId] = list;

                Navigator.of(ctx).pop();
                setState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Surge rate rule "$reason" (${mult}x) activated!'),
                    backgroundColor: Colors.purple.shade800,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitsTab(String resortId) {
    final units = _store.resortUnits[resortId] ?? [];
    final rates = _store.resortRateRules[resortId] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Resort Unit Inventory',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Unit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.bookingActionBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _openAddUnitDialog(resortId),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (units.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text('No accommodation units found in resort inventory.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            )
          else
            ...units.map((u) {
              Color statusColor = Colors.green;
              if (u.status == 'maintenance') statusColor = Colors.orange;
              if (u.status == 'occupied') statusColor = Colors.blue;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.meeting_room, color: Colors.white, size: 22),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          u.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          u.status.toUpperCase(),
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Type: ${u.type.toUpperCase()} | Capacity: ${u.capacity} Guests\n${u.description}'),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₹${u.pricePerNight.toStringAsFixed(2)}\n/ night',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryTeal, fontSize: 13),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        tooltip: 'Delete Unit',
                        onPressed: () {
                          setState(() {
                            units.remove(u);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Unit "${u.name}" removed from resort inventory.')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Dynamic Rate Rules',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.trending_up, size: 18),
                label: const Text('Add Surge Rule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _openAddRateRuleDialog(resortId),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rates.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text('No dynamic surge rate rules active.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ),
            )
          else
            ...rates.map((rr) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      backgroundColor: Colors.purple,
                      child: Icon(Icons.trending_up, color: Colors.white, size: 22),
                    ),
                    title: Text(rr.reason, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Dates: ${rr.startDate.toString().split(' ')[0]} to ${rr.endDate.toString().split(' ')[0]}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Text(
                            '${rr.priceMultiplier}x Multiplier',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          tooltip: 'Delete Surge Rule',
                          onPressed: () {
                            setState(() {
                              rates.remove(rr);
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Surge rule "${rr.reason}" deleted.')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildAccountsTab(String resortId, report) {
    final resort = _store.resorts[resortId];
    final expenses = _store.resortExpenses[resortId] ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Resort Financial Accounting', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primarySlate)),
          const SizedBox(height: 14),
          Card(
            color: AppTheme.primarySlate,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('Total Net Revenue (Month)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text('₹${report.netProfit.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildTierSubscriptionCard(resortId, resort),
          const SizedBox(height: 20),
          _buildResortAccountantCard(resortId),
          const SizedBox(height: 24),
          const Text('Logged Expenses', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primarySlate)),
          const SizedBox(height: 12),
          ...expenses.map((e) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(e.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Category: ${e.category} | Date: ${e.expenseDate.toString().split(' ')[0]}'),
                  trailing: Text('-₹${e.amount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              )),
        ],
      ),
    );
  }

  void _openAddInchargeDialog(String resortId) {
    final resort = _store.resorts[resortId];
    if (resort == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AssignInchargeDialog(resort: resort),
    ).then((updated) {
      if (updated == true) {
        setState(() {});
      }
    });
  }


  void _confirmRemoveIncharge(String resortId, String inchargeName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Remove Incharge?'),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "$inchargeName" as the Operations Incharge for this resort?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Incharge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _store.removeInchargeForResort(resortId);
              Navigator.of(ctx).pop();
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Operations Incharge removed from resort.'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _openAssignWorkToInchargeDialog(String resortId, String inchargeId) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Operations';
    String priority = 'high';
    String targetHours = '4';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.assignment_ind, color: AppTheme.bookingNavy, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Assign Work to Incharge', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 520 ? 480 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Assign operational directives, tasks, or safety audits directly to the Operations Incharge.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Work / Task Title *',
                      hintText: 'e.g. Conduct Monthly Fire Safety & Kitchen Audit',
                      prefixIcon: Icon(Icons.task_alt, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: category,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Category'),
                          items: const [
                            DropdownMenuItem(value: 'Operations', child: Text('Operations', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Housekeeping', child: Text('Housekeeping', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'F&B Fulfillment', child: Text('F&B', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Safety & Security', child: Text('Safety', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'Guest Services', child: Text('Guest Services', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => category = val);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: priority,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Priority'),
                          items: const [
                            DropdownMenuItem(value: 'high', child: Text('🔥 High', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'medium', child: Text('⚡ Medium', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'low', child: Text('🟢 Low', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => priority = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: targetHours,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Target Completion Time'),
                    items: const [
                      DropdownMenuItem(value: '2', child: Text('Within 2 Hours (Urgent)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: '4', child: Text('Within 4 Hours', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: '12', child: Text('Within 12 Hours (Today)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: '24', child: Text('Within 24 Hours (Tomorrow)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: '48', child: Text('Within 48 Hours', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: '168', child: Text('Within 1 Week', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => targetHours = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Work Instructions / Details',
                      hintText: 'Provide detailed instructions or checklist items for the incharge...',
                    ),
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
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Assign Work'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.bookingActionBlue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;

                final hours = int.tryParse(targetHours) ?? 4;
                final newTask = StaffTask(
                  id: 'task-mgr-${DateTime.now().millisecondsSinceEpoch}',
                  resortId: resortId,
                  inchargeId: inchargeId,
                  assignedToStaffId: null,
                  title: titleCtrl.text.trim(),
                  description: '[$category] ${descCtrl.text.trim()}',
                  priority: priority,
                  status: 'pending',
                  dueDate: DateTime.now().add(Duration(hours: hours)),
                  createdAt: DateTime.now(),
                );

                final list = _store.resortTasks[resortId] ?? [];
                list.insert(0, newTask);
                _store.resortTasks[resortId] = list;

                Navigator.of(ctx).pop();
                setState(() {});

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Work "${newTask.title}" assigned to Operations Incharge!'),
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

  Widget _buildInchargeTab(String resortId) {
    final incharge = _store.getInchargeForResort(resortId);
    final allTasks = _store.resortTasks[resortId] ?? [];
    // Tasks assigned directly by Manager to Incharge (or supervised by Incharge)
    final inchargeTasks = allTasks.where((t) => t.assignedToStaffId == null || t.inchargeId == incharge?.id).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Resort Operations Incharge',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (incharge == null)
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Add Incharge'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.bookingActionBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _openAddInchargeDialog(resortId),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rule: Exactly 1 Operations Incharge per resort. The Incharge manages staff members, daily maintenance work, F&B orders, and operational tasks.',
            style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade600),
          ),
          const SizedBox(height: 20),

          if (incharge != null) ...[
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Colors.indigo.shade100,
                          child: Icon(Icons.engineering, color: Colors.indigo.shade900, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    incharge.fullName,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'ACTIVE INCHARGE',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Email: ${incharge.email}\nPhone: ${incharge.phone}',
                                style: const TextStyle(fontSize: 12, color: Colors.blueGrey, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.badge_outlined, size: 18),
                          label: const Text('Change / Assign Incharge'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.resortCharcoal,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _openAddInchargeDialog(resortId),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.payments_outlined, size: 18),
                          label: const Text('Disburse Incharge Salary'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _openDisburseInchargeSalaryDialog(resortId, incharge),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.assignment_ind, size: 18),
                          label: const Text('Assign Work to Incharge'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.bookingActionBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _openAssignWorkToInchargeDialog(resortId, incharge.id),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                          label: const Text('Delete / Remove Incharge', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => _confirmRemoveIncharge(resortId, incharge.fullName),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Work Assigned to Operations Incharge',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    '${inchargeTasks.length} Directives',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (inchargeTasks.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.assignment_turned_in_outlined, size: 36, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('No active work assigned to the Incharge yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Assign First Work Directive'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.bookingActionBlue,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => _openAssignWorkToInchargeDialog(resortId, incharge.id),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              ...inchargeTasks.map((t) {
                Color priorityColor = Colors.orange;
                if (t.priority == 'high') priorityColor = Colors.red;
                if (t.priority == 'low') priorityColor = Colors.green;

                Color statusBg = Colors.amber.shade100;
                Color statusFg = Colors.amber.shade900;
                if (t.status == 'in_progress') {
                  statusBg = Colors.blue.shade100;
                  statusFg = Colors.blue.shade900;
                } else if (t.status == 'completed') {
                  statusBg = Colors.green.shade100;
                  statusFg = Colors.green.shade900;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                t.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: priorityColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                t.priority.toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: priorityColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (t.description.isNotEmpty) ...[
                          Text(
                            t.description,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.schedule, size: 14, color: Colors.blueGrey.shade400),
                                const SizedBox(width: 4),
                                Text(
                                  t.dueDate != null
                                      ? 'Target: ${t.dueDate.toString().split(' ')[0]} ${t.dueDate.toString().split(' ')[1].substring(0, 5)}'
                                      : 'No Due Date',
                                  style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(4)),
                                  child: Text(
                                    t.status.replaceAll('_', ' ').toUpperCase(),
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusFg),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: t.status,
                                      isDense: true,
                                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                                      items: const [
                                        DropdownMenuItem(value: 'pending', child: Text('Pending', style: TextStyle(fontSize: 11))),
                                        DropdownMenuItem(value: 'in_progress', child: Text('In Progress', style: TextStyle(fontSize: 11))),
                                        DropdownMenuItem(value: 'completed', child: Text('Completed', style: TextStyle(fontSize: 11))),
                                      ],
                                      onChanged: (newStatus) {
                                        if (newStatus != null) {
                                          setState(() {
                                            final list = _store.resortTasks[resortId] ?? [];
                                            final idx = list.indexWhere((item) => item.id == t.id);
                                            if (idx != -1) {
                                              list[idx] = t.copyWith(status: newStatus);
                                            }
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Incharge Salary Disbursements',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Disburse Salary'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onPressed: () => _openDisburseInchargeSalaryDialog(resortId, incharge),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInchargeSalaryHistoryList(resortId, incharge),
            const SizedBox(height: 24),
            _buildStaffFundRequestsSection(resortId),
          ] else ...[
            Card(
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.amber.shade300)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.person_add_disabled, size: 40, color: Colors.amber.shade900),
                    const SizedBox(height: 12),
                    Text('No Incharge Currently Assigned', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    const SizedBox(height: 6),
                    const Text(
                      'This resort currently has no designated Operations Incharge. Click below to add an incharge to manage staff and maintenance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Operations Incharge'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.bookingActionBlue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => _openAddInchargeDialog(resortId),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String val, IconData icon, MaterialColor color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.shade50, shape: BoxShape.circle),
                  child: Icon(icon, color: color.shade800, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                val,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInchargeSalaryHistoryList(String resortId, UserProfile incharge) {
    final payments = _store.inchargeSalaryPayments[resortId] ?? [];

    if (payments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('No salary disbursements logged yet for ${incharge.fullName}.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: payments.map((p) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade50,
              child: const Icon(Icons.currency_rupee, color: Colors.green),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Salary: ${p.monthYear}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  '₹${p.amount.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mode: ${p.paymentMode} | Ref / UTR: ${p.transactionRef}',
                      style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
                  Text(
                    'Disbursed on: ${p.disbursedAt.toString().split(' ')[0]} to ${p.inchargeName}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Text(
                'PAID & EXPENSED',
                style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 10),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _openDisburseInchargeSalaryDialog(String resortId, UserProfile incharge) {
    final monthCtrl = TextEditingController(text: 'September 2026');
    final amountCtrl = TextEditingController(text: '45000.00');
    final refCtrl = TextEditingController(text: 'UTR-INC-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final notesCtrl = TextEditingController();
    String paymentMode = 'Bank Transfer / NEFT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                child: const Icon(Icons.payments, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Disburse Incharge Salary', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
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
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE7E5E4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: AppTheme.resortCharcoal, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recipient: ${incharge.fullName} (${incharge.email})',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.resortDarkText),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: monthCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Payroll Month & Year *',
                      hintText: 'e.g. September 2026',
                      prefixIcon: Icon(Icons.calendar_month, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Salary Amount (₹) *',
                      prefixIcon: Icon(Icons.currency_rupee, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: const InputDecoration(
                      labelText: 'Payment Mode',
                      prefixIcon: Icon(Icons.account_balance, size: 20),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Bank Transfer / NEFT', child: Text('Bank Transfer / NEFT')),
                      DropdownMenuItem(value: 'UPI Transfer', child: Text('UPI Transfer')),
                      DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                      DropdownMenuItem(value: 'Cash Voucher', child: Text('Cash Voucher')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => paymentMode = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Transaction Reference / UTR Number *',
                      hintText: 'e.g. UTR-9823412',
                      prefixIcon: Icon(Icons.tag, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Notes / Remarks (Optional)',
                      hintText: 'Includes quarterly performance incentive',
                      prefixIcon: Icon(Icons.note_alt_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '⚠️ Note: Disbursing salary will automatically log a resort expense under "staff_salary", updating your net profit in real time.',
                    style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Disburse & Record Expense'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final month = monthCtrl.text.trim();
                final ref = refCtrl.text.trim();

                if (amt <= 0 || month.isEmpty || ref.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all required salary fields.')),
                  );
                  return;
                }

                _store.disburseInchargeSalary(
                  resortId: resortId,
                  inchargeEmail: incharge.email,
                  inchargeName: incharge.fullName,
                  amount: amt,
                  monthYear: month,
                  paymentMode: paymentMode,
                  transactionRef: ref,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );

                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Salary of ₹${amt.toStringAsFixed(2)} disbursed to ${incharge.fullName} and expensed!'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierSubscriptionCard(String resortId, Resort? resort) {
    final activeReq = _store.tierChangeRequests.where((r) => r.resortId == resortId).firstOrNull;
    final tier = resort?.subscriptionTier ?? SubscriptionTier.basic;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 14,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star, color: Colors.orange, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ResortHub Subscription Plan',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                        ),
                        Text(
                          'Current Active Tier: ${tier.badgeText}',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upgrade, size: 18),
                  label: const Text('Change / Upgrade Tier'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.resortCoral,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _openChangeTierDialog(resortId),
                ),
              ],
            ),
            if (activeReq != null) ...[
              const Divider(height: 24),
              if (activeReq.status == TierRequestStatus.pendingPaymentDetails) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top, color: Colors.orange, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tier Change Request Submitted: Upgrade to ${activeReq.requestedTier.badgeText}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Super Admin has received your request and will send official payment details (Bank/UPI) shortly.',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Awaiting Superadmin', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ] else if (activeReq.status == TierRequestStatus.awaitingAdminPayment) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade400, width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.payment, color: Colors.green, size: 24),
                              const SizedBox(width: 10),
                              Text(
                                'Payment Details for ${activeReq.requestedTier.badgeText}',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade900),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text('Amount: ₹${activeReq.amountDue.toStringAsFixed(2)}',
                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900, fontSize: 12)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Text(
                          activeReq.paymentInstructions ?? 'Bank / UPI instructions provided by Super Admin',
                          style: const TextStyle(fontSize: 13, height: 1.4, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('I Have Paid - Submit UTR Reference to Activate Tier'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openSubmitTierPaymentDialog(activeReq),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (activeReq.status == TierRequestStatus.completed) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.blue, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tier Change Completed: Upgraded to ${activeReq.requestedTier.badgeText} (Ref: ${activeReq.adminPaymentRef ?? 'Paid'}). Active.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _openChangeTierDialog(String resortId) {
    SubscriptionTier selectedTier = SubscriptionTier.premium;
    final resort = _store.resorts[resortId];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.upgrade, color: AppTheme.resortCoral),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Request Tier Upgrade',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Tier: ${resort?.subscriptionTier.badgeText ?? "Basic"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text('Select Target Tier to Request:', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              DropdownButtonFormField<SubscriptionTier>(
                value: selectedTier,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: const [
                  DropdownMenuItem(value: SubscriptionTier.basic, child: Text('Basic Plan (₹199/mo)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: SubscriptionTier.superTier, child: Text('Super Plan (₹499/mo)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: SubscriptionTier.premium, child: Text('Premium Plan (₹899/mo)', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedTier = val);
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.resortCoral.withOpacity(0.2)),
                ),
                child: const Text(
                  'Note: Once you submit this request, Super Admin will review it and dispatch official platform payment details (Bank account / UPI). Upon payment and UTR submission, your resort tier will immediately update.',
                  style: TextStyle(fontSize: 11, color: AppTheme.resortDarkText, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.resortCoral, foregroundColor: Colors.white),
                  onPressed: () {
                    _store.requestTierChange(resortId: resortId, requestedTier: selectedTier);
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Tier change request to ${selectedTier.badgeText} sent to Super Admin.'),
                        backgroundColor: Colors.green.shade800,
                      ),
                    );
                  },
                  child: const Text('Submit Request to Super Admin'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openSubmitTierPaymentDialog(TierChangeRequest req) {
    final utrCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.receipt_long, color: Colors.green),
            SizedBox(width: 8),
            Text('Confirm Payment & Activate Tier'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tier: ${req.requestedTier.badgeText} | Amount Paid: ₹${req.amountDue.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: utrCtrl,
              decoration: const InputDecoration(
                labelText: 'Transaction Reference / UTR Number *',
                hintText: 'e.g. UTR-9082348123',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Enter the bank/UPI reference number generated after transferring the fee. The system will activate your new tier immediately upon confirmation.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 6,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                onPressed: () {
                  final ref = utrCtrl.text.trim();
                  if (ref.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please provide the transaction reference / UTR number.')),
                    );
                    return;
                  }
                  _store.confirmTierPayment(requestId: req.id, adminPaymentRef: ref);
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Payment confirmed! Resort upgraded to ${req.requestedTier.badgeText} plan.'),
                      backgroundColor: Colors.green.shade800,
                    ),
                  );
                },
                child: const Text('Confirm Payment & Update Tier'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Resort Dedicated Accountant Section ---

  Widget _buildResortAccountantCard(String resortId) {
    final accountant = _store.getAssignedAccountantForResort(resortId);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  radius: 20,
                  child: const Icon(Icons.account_balance, color: Colors.teal, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resort Dedicated Accountant',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Separate financial login scoped to this resort',
                        style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: Icon(accountant != null ? Icons.manage_accounts : Icons.person_add, size: 16),
                label: Text(accountant != null ? 'Change / Add Accountant' : 'Add Resort Accountant'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.resortCharcoal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _openAddAccountantDialog(resortId),
              ),
            ),
            const SizedBox(height: 16),
            if (accountant != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFFEBB02),
                      radius: 22,
                      child: Text(
                        accountant.fullName.isNotEmpty ? accountant.fullName[0].toUpperCase() : 'A',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.resortDarkText, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(accountant.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                                child: Text('ACTIVE ACCOUNTANT', style: TextStyle(color: Colors.green.shade900, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text('Login Email: ${accountant.email}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
                          if (accountant.phone != null)
                            Text('Phone: ${accountant.phone}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.orange, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No dedicated accountant registered for this resort yet. Click "Add Resort Accountant" to create separate login credentials.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openAddAccountantDialog(String resortId) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passwordCtrl = TextEditingController(text: 'accountant123');

    final resort = _store.resorts[resortId];
    if (resort != null) {
      final sanitizedName = resort.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
      emailCtrl.text = 'accountant@$sanitizedName.com';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.person_add, color: AppTheme.resortCoral),
            SizedBox(width: 10),
            Text('Add Resort Accountant'),
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
                  'Create dedicated accountant credentials for ${resort?.name ?? "this resort"}. When logging in, this accountant will be locked to this resort\'s finances.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'e.g. Anand Joshi',
                    prefixIcon: Icon(Icons.person, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Login Email Address *',
                    hintText: 'e.g. accountant@resort.com',
                    prefixIcon: Icon(Icons.email, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    hintText: '+91 98765 00000',
                    prefixIcon: Icon(Icons.phone, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Accountant Password *',
                    hintText: 'Initial temporary password',
                    prefixIcon: Icon(Icons.lock, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.resortCoral,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passwordCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter name, email, and password.')),
                );
                return;
              }
              final newAcc = _store.addAccountantForResort(
                resortId: resortId,
                fullName: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                password: passwordCtrl.text.trim(),
                phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
              );
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Accountant "${newAcc.fullName}" added successfully for ${resort?.name ?? "resort"}! Email: ${newAcc.email}'),
                  backgroundColor: Colors.green.shade800,
                ),
              );
            },
            child: const Text('Add Accountant'),
          ),
        ],
      ),
    );
  }

  // --- Staff Salary Fund Requests from Incharge Section ---

  Widget _buildStaffFundRequestsSection(String resortId) {
    final requests = _store.getStaffSalaryFundRequests(resortId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Staff Salary Fund Requests from Incharge',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.primarySlate),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Text(
                '${requests.where((r) => r.status == StaffFundRequestStatus.pending).length} Pending Release',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Incharge calculates ground staff wage requirements and bills Admin. Approve and transfer funds to release staff payroll.',
          style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade600),
        ),
        const SizedBox(height: 12),
        if (requests.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('No staff payroll fund requests from Incharge yet.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ),
            ),
          )
        else
          ...requests.map((req) {
            final isPending = req.status == StaffFundRequestStatus.pending;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isPending ? Colors.amber.shade300 : Colors.green.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              backgroundColor: isPending ? Colors.amber.shade100 : Colors.green.shade100,
                              radius: 18,
                              child: Icon(
                                isPending ? Icons.pending_actions : Icons.check_circle_outline,
                                color: isPending ? Colors.amber.shade900 : Colors.green.shade900,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cycle: ${req.monthYear}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                Text(
                                  'Requested by: ${req.inchargeName} (${req.staffCount} Staff Members)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPending ? Colors.amber.shade100 : Colors.green.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isPending ? 'PENDING ADMIN TRANSFER' : 'FUNDED & DISBURSED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isPending ? Colors.amber.shade900 : Colors.green.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Requested Amount:', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                        Text('₹${req.requestedAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                      ],
                    ),
                    if (req.notes != null && req.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Incharge Note: "${req.notes}"', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.blueGrey.shade700)),
                    ],
                    if (!isPending && req.transactionRef != null) ...[
                      const SizedBox(height: 6),
                      Text('Payment Ref: ${req.paymentMode ?? "Bank"} (UTR: ${req.transactionRef})',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                    ],
                    if (isPending) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send_to_mobile, size: 18),
                          label: const Text('Review & Transfer Staff Payroll Funds'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _openTransferStaffFundsDialog(resortId, req),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  void _openTransferStaffFundsDialog(String resortId, StaffSalaryFundRequest req) {
    final amountCtrl = TextEditingController(text: req.requestedAmount.toStringAsFixed(2));
    final refCtrl = TextEditingController(text: 'UTR-STAFF-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final notesCtrl = TextEditingController();
    String paymentMode = 'Bank Transfer / NEFT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.payments, color: Colors.green),
              SizedBox(width: 10),
              Text('Transfer Staff Funds to Incharge'),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width > 500 ? 460 : double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Incharge: ${req.inchargeName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('Billing Cycle: ${req.monthYear} (${req.staffCount} Ground Staff)', style: const TextStyle(fontSize: 12)),
                        if (req.notes != null)
                          Text('Note: ${req.notes}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Disbursed Amount (₹) *',
                      prefixIcon: Icon(Icons.currency_rupee, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    decoration: const InputDecoration(
                      labelText: 'Fund Transfer Mode *',
                      prefixIcon: Icon(Icons.account_balance_wallet, size: 20),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Bank Transfer / NEFT', child: Text('Bank Transfer / NEFT')),
                      DropdownMenuItem(value: 'UPI Transfer', child: Text('UPI Transfer')),
                      DropdownMenuItem(value: 'Company Cash Advance', child: Text('Company Cash Advance')),
                      DropdownMenuItem(value: 'Cheque Payment', child: Text('Cheque Payment')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => paymentMode = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Bank / UPI Transaction Reference (UTR) *',
                      hintText: 'e.g. UTR-1234567890',
                      prefixIcon: Icon(Icons.tag, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Admin Notes (Optional)',
                      hintText: 'e.g. Released for September salary cycle',
                      prefixIcon: Icon(Icons.note_alt_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                final ref = refCtrl.text.trim();
                if (amt <= 0 || ref.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter valid amount and transaction reference.')),
                  );
                  return;
                }
                _store.approveAndDisburseStaffFunds(
                  requestId: req.id,
                  fundedAmount: amt,
                  paymentMode: paymentMode,
                  transactionRef: ref,
                  adminNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                );
                Navigator.pop(ctx);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Payroll funds of ₹${amt.toStringAsFixed(2)} transferred to ${req.inchargeName} and expensed!'),
                    backgroundColor: Colors.green.shade800,
                  ),
                );
              },
              child: const Text('Confirm & Transfer Funds'),
            ),
          ],
        ),
      ),
    );
  }
}


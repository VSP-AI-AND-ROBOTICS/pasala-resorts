import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/report.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class AccountantDashboardPage extends StatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  State<AccountantDashboardPage> createState() => _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends State<AccountantDashboardPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;
  String? _selectedResortId; // null = Platform-Wide All Accounts

  @override
  void initState() {
    super.initState();
    final user = _store.currentUser;
    final isResortScoped = user != null && user.role == AppRole.accountant && user.resortId != null;
    if (isResortScoped) {
      _selectedResortId = user.resortId;
    }
    _tabController = TabController(length: isResortScoped ? 2 : 3, vsync: this);
  }

  void _ensureTabController(int targetCount) {
    if (_tabController.length != targetCount) {
      _tabController.dispose();
      _tabController = TabController(length: targetCount, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _store.currentUser;
    final isResortScoped = currentUser != null && currentUser.role == AppRole.accountant && currentUser.resortId != null;
    final targetTabCount = isResortScoped ? 2 : 3;
    _ensureTabController(targetTabCount);

    if (isResortScoped && _selectedResortId != currentUser.resortId) {
      _selectedResortId = currentUser.resortId;
    }

    final report = _selectedResortId == null
        ? _store.getPlatformAccountantReport()
        : _store.getDashboardReport(_selectedResortId!);

    final resortsList = _store.resorts.values.toList();
    final selectedResortName = _selectedResortId == null
        ? 'Platform-Wide (All Subscribed Resorts)'
        : (_store.resorts[_selectedResortId]?.name ?? 'Resort');

    final isDark = AppTheme.isDark(context);
    final pageBg = AppTheme.pageBg(context);
    final cardBg = AppTheme.cardBg(context);
    final border = AppTheme.border(context);
    final textPrimary = AppTheme.textPrimary(context);
    final textMuted = AppTheme.textMuted(context);

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ResortHub Accountant Portal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textPrimary),
            ),
            Text(
              'Viewing: $selectedResortName',
              style: TextStyle(fontSize: 12, color: textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: cardBg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: border, width: 1)),
        actions: [
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
          indicatorColor: isDark ? AppTheme.resortMintPrimary : AppTheme.resortCoral,
          indicatorWeight: 3,
          labelColor: isDark ? AppTheme.resortMintPrimary : AppTheme.resortCoral,
          unselectedLabelColor: textMuted,
          isScrollable: true,
          tabs: isResortScoped
              ? const [
                  Tab(icon: Icon(Icons.account_balance), text: 'Revenue Overview'),
                  Tab(icon: Icon(Icons.fastfood), text: 'Food & Sales'),
                ]
              : const [
                  Tab(icon: Icon(Icons.account_balance), text: 'Revenue Overview'),
                  Tab(icon: Icon(Icons.apartment), text: 'All Resort Accounts'),
                  Tab(icon: Icon(Icons.fastfood), text: 'Food & Sales'),
                ],
        ),
      ),
      body: Column(
        children: [
          // Filter / Scope Bar
          if (isResortScoped)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock, color: AppTheme.resortGold, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assigned Resort: ${_store.resorts[currentUser.resortId]?.name ?? "Resort"} (Locked)',
                      style: const TextStyle(color: AppTheme.resortDarkText, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppTheme.resortGold.withOpacity(0.4)),
                    ),
                    child: const Text('Resort Accountant', style: TextStyle(color: AppTheme.resortGold, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFE7E5E4))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public, color: AppTheme.resortCoral, size: 18),
                  const SizedBox(width: 8),
                  const Text('Scope:', style: TextStyle(color: AppTheme.resortDarkText, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBFBF9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE7E5E4)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _selectedResortId,
                          isExpanded: true,
                          dropdownColor: Colors.white,
                          style: const TextStyle(color: AppTheme.resortDarkText, fontSize: 12),
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.resortDarkText),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('🌐 All Subscribed Resorts (Platform-Wide)', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.resortCoral), overflow: TextOverflow.ellipsis),
                            ),
                            ...resortsList.map(
                              (r) => DropdownMenuItem<String?>(
                                value: r.id,
                                child: Text('${r.name} (${r.city})', overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedResortId = val);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: isResortScoped
                  ? [
                      _buildOverviewTab(report),
                      _buildSalesTab(report),
                    ]
                  : [
                      _buildOverviewTab(report),
                      _buildAllResortsAccountsTab(),
                      _buildSalesTab(report),
                    ],
            ),
          ),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildOverviewTab(DashboardReport report) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: AppTheme.resortCharcoal,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                children: [
                  Text(
                    _selectedResortId == null
                        ? 'TOTAL PLATFORM NET REVENUE (ALL RESORTS)'
                        : 'TOTAL NET PROFIT (MONTH TO DATE)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '₹${report.netProfit.toStringAsFixed(2)}',
                      style: const TextStyle(color: Color(0xFFFEBB02), fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Text('Revenue', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('₹${report.monthRevenue.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.white24),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('Expenses', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('₹${report.monthExpenses.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 28, color: Colors.white24),
                      Expanded(
                        child: Column(
                          children: [
                            const Text('Net Margin', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                report.monthRevenue > 0
                                    ? '${((report.netProfit / report.monthRevenue) * 100).toStringAsFixed(1)}%'
                                    : '0.0%',
                                style: const TextStyle(color: Color(0xFFFEBB02), fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Financial Breakdown & Cost Centers', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Room Bookings', style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₹${(report.monthRevenue - report.foodSalesRevenue).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Food & Beverage', style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₹${report.foodSalesRevenue.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Expenses', style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₹${report.monthExpenses.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Occupancy Rate', style: TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('${(report.occupancyRate * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllResortsAccountsTab() {
    final resorts = _store.resorts.values.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: resorts.length,
      itemBuilder: (context, index) {
        final resort = resorts[index];
        final rep = _store.getDashboardReport(resort.id);
        final sal = _store.getTotalSalaryExpenses(resort.id);

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(resort.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${resort.city}, ${resort.state}', style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Text(
                        resort.subscriptionTier.badgeText,
                        style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    _accountStat('Revenue', '₹${rep.monthRevenue.toStringAsFixed(0)}', Colors.blue.shade900),
                    const SizedBox(width: 4),
                    _accountStat('Salaries', '₹${sal.toStringAsFixed(0)}', Colors.red.shade800),
                    const SizedBox(width: 4),
                    _accountStat('Expenses', '₹${rep.monthExpenses.toStringAsFixed(0)}', Colors.grey.shade800),
                    const SizedBox(width: 4),
                    _accountStat('Net Margin', '₹${rep.netProfit.toStringAsFixed(0)}', Colors.green.shade800),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('Inspect Resort Accounts'),
                    onPressed: () {
                      setState(() {
                        _selectedResortId = resort.id;
                        _tabController.animateTo(0);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _accountStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }


  Widget _buildSalesTab(DashboardReport report) {
    final allFoodOrders = _selectedResortId == null
        ? _store.resortFoodOrders.values.expand((orders) => orders).toList()
        : (_store.resortFoodOrders[_selectedResortId] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Food & Restaurant Revenue', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('₹${report.foodSalesRevenue.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.restaurant, size: 36, color: Colors.orange.shade400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Food Orders & Sales Audit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (allFoodOrders.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No food orders recorded.')))
          else
            ...allFoodOrders.map((fo) {
              final resort = _store.resorts[fo.resortId];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order #${fo.id} - ${resort?.name ?? "Resort"} (${fo.roomNumber})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 3),
                            Text('Items: ${fo.items.length} items • Status: ${fo.status}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('₹${fo.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

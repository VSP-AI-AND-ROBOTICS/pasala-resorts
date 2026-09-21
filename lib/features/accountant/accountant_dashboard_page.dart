import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/report.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class AccountantDashboardPage extends StatefulWidget {
  const AccountantDashboardPage({super.key});

  @override
  State<AccountantDashboardPage> createState() => _AccountantDashboardPageState();
}

class _AccountantDashboardPageState extends State<AccountantDashboardPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final report = _store.getPlatformAccountantReport();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accountant Portal: Platform-Wide (Total App)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF1F2533),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFE23744)),
            onPressed: () { MockDataStore.instance.logout(); context.go('/login'); },
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFE23744),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance), text: 'Net Overview'),
            Tab(icon: Icon(Icons.fastfood), text: 'Food & Sales'),
            Tab(icon: Icon(Icons.receipt), text: 'Ledger Settlements'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(report),
          _buildSalesTab(report),
          _buildLedgerTab(),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildOverviewTab(DashboardReport report) {
    final allExpenses = _store.resortExpenses.values.expand((exps) => exps).toList();
    final allPayments = _store.bookingPayments;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: Colors.indigo.shade800,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('PLATFORM TOTAL NET PROFIT (MONTH TO DATE)', style: TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Text('₹${report.netProfit.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Total App Revenue', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${report.monthRevenue.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      Column(
                        children: [
                          const Text('Total Platform Expenses', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('₹${report.monthExpenses.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Platform Customer Booking Payments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...allPayments.map((p) {
            final resort = _store.resorts[p.resortId];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.payment, color: Colors.indigo),
                title: Text('Txn: ${p.transactionRef} (${resort?.name ?? "Resort"})'),
                subtitle: Text('Kind: ${p.paymentKind.name.toUpperCase()} | Key: ${p.idempotencyKey}'),
                trailing: Text('₹${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
              ),
            );
          }),
          const SizedBox(height: 24),
          const Text('All Operating Expense Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...allExpenses.map((e) {
            final resort = _store.resorts[e.resortId];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.receipt_long, color: Colors.red),
                title: Text('${e.description} (${resort?.name ?? "Resort"})'),
                subtitle: Text('Category: ${e.category} | Date: ${e.expenseDate.toString().split(' ')[0]}'),
                trailing: Text('-₹${e.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSalesTab(DashboardReport report) {
    final allFoodOrders = _store.resortFoodOrders.values.expand((orders) => orders).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Total F&B Sales', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('₹${report.foodSalesRevenue.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  color: Colors.purple.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Activity & Experience Sales', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Text('₹${report.activitySalesRevenue.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple.shade900)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Total Food Order Ledger Audit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...allFoodOrders.map((fo) {
            final resort = _store.resorts[fo.resortId];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('Order #${fo.id} - ${resort?.name ?? "Resort"} (${fo.roomNumber})'),
                subtitle: Text('Items: ${fo.items.length} items | Status: ${fo.status}'),
                trailing: Text('₹${fo.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildLedgerTab() {
    final allSettlements = _store.resortLedgerSettlements.values.expand((s) => s).toList();

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: allSettlements.length,
      itemBuilder: (context, index) {
        final s = allSettlements[index];
        final resort = _store.resorts[s.resortId];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
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
                        'Settlement #${s.id} - ${resort?.name ?? "Resort"}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text(s.status.toUpperCase(), style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Period: ${s.periodStart.toString().split(' ')[0]} to ${s.periodEnd.toString().split(' ')[0]}'),
                Text('Gross Rev: ₹${s.totalRevenue.toStringAsFixed(2)} | Platform Fee: ₹${s.platformFee.toStringAsFixed(2)}'),
                const Divider(height: 20),
                Text('Payout Settlement: ₹${s.payoutAmount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16)),
              ],
            ),
          ),
        );
      },
    );
  }
}

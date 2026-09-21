import 'package:flutter/material.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/widgets/resort_inspector_header.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final MockDataStore _store = MockDataStore.instance;

  @override
  Widget build(BuildContext context) {
    final selectedId = _store.superAdminSelectedResortId;
    final inspectedResort = selectedId != null ? _store.resorts[selectedId] : null;

    final report = selectedId != null
        ? _store.getDashboardReport(selectedId)
        : _store.getPlatformAccountantReport();

    return Scaffold(
      appBar: AppBar(
        title: Text(inspectedResort != null ? 'Reports: ${inspectedResort.name}' : 'Cross-Resort Platform Reports'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ResortInspectorHeader(onResortChanged: () => setState(() {})),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inspectedResort != null
                        ? 'Resort Operational & Financial Summary (${inspectedResort.subscriptionTier.badgeText} Tier)'
                        : 'Aggregate Co-owner Financial & Performance Overview',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 1.6,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildMetricCard('Today Revenue', '₹${report.todayRevenue.toStringAsFixed(2)}', Icons.today, Colors.green),
                      _buildMetricCard('Month Revenue', '₹${report.monthRevenue.toStringAsFixed(2)}', Icons.calendar_month, Colors.teal),
                      _buildMetricCard('Monthly Expenses', '₹${report.monthExpenses.toStringAsFixed(2)}', Icons.money_off, Colors.red),
                      _buildMetricCard('Net Profit', '₹${report.netProfit.toStringAsFixed(2)}', Icons.account_balance, Colors.blue),
                      _buildMetricCard('Occupancy Rate', '${report.occupancyRate.toStringAsFixed(1)}%', Icons.king_bed, Colors.amber),
                      _buildMetricCard('Upcoming Arrivals', '${report.upcomingArrivals}', Icons.luggage, Colors.indigo),
                      _buildMetricCard('Food Sales', '₹${report.foodSalesRevenue.toStringAsFixed(2)}', Icons.fastfood, Colors.orange),
                      _buildMetricCard('Cancellations', '${report.cancellationsCount}', Icons.cancel, Colors.deepOrange),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Resort Breakdown Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ..._store.resorts.values.map((resort) {
                    final r = _store.getDashboardReport(resort.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(resort.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Tier: ${resort.subscriptionTier.badgeText} | Occupancy: ${r.occupancyRate}%'),
                        trailing: Text(
                          '₹${r.monthRevenue.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 15),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

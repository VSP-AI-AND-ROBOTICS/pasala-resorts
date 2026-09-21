import 'package:flutter/material.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/widgets/resort_inspector_header.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class PaymentManagementPage extends StatefulWidget {
  const PaymentManagementPage({super.key});

  @override
  State<PaymentManagementPage> createState() => _PaymentManagementPageState();
}

class _PaymentManagementPageState extends State<PaymentManagementPage> with SingleTickerProviderStateMixin {
  final MockDataStore _store = MockDataStore.instance;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Payment Management'),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.subscriptions), text: 'Subscription Payments (Resort -> Owner)'),
            Tab(icon: Icon(Icons.book_online), text: 'Customer Booking Payments'),
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
                _buildSubscriptionPaymentsTab(),
                _buildBookingPaymentsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildSubscriptionPaymentsTab() {
    final subPayments = _store.subscriptionPayments;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: subPayments.length,
      itemBuilder: (context, index) {
        final p = subPayments[index];
        final resort = _store.resorts[p.resortId];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.purple,
              child: Icon(Icons.business, color: Colors.white),
            ),
            title: Text(resort?.name ?? 'Unknown Resort', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Txn Ref: ${p.transactionRef}\nIdempotency Key: ${p.idempotencyKey}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(p.status.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookingPaymentsTab() {
    final bkgPayments = _store.bookingPayments;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bkgPayments.length,
      itemBuilder: (context, index) {
        final p = bkgPayments[index];
        final resort = _store.resorts[p.resortId];

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.shade700,
              child: const Icon(Icons.receipt_long, color: Colors.white),
            ),
            title: Text('${resort?.name ?? "Resort"} - ${p.paymentKind.name.toUpperCase()} Payment'),
            subtitle: Text('Txn Ref: ${p.transactionRef}\nGateway: ${p.gatewayProvider} | Key: ${p.idempotencyKey}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(p.status.name.toUpperCase(),
                      style: TextStyle(fontSize: 10, color: Colors.teal.shade900, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

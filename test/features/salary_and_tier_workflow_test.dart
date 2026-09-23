import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/models/resort.dart';
import 'package:pasala/core/models/salary_disbursement.dart';
import 'package:pasala/core/services/mock_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ResortHub Salary & Tier Workflow Unit Tests', () {
    late MockDataStore store;

    setUp(() {
      store = MockDataStore.instance;
    });

    test('1. Admin disburses salary to Incharge and automatically records expense', () {
      const resortId = 'resort-grand-palms';
      final initialExpenses = store.resortExpenses[resortId]?.length ?? 0;
      final initialSalaryTotal = store.getTotalSalaryExpenses(resortId);

      final payment = store.disburseInchargeSalary(
        resortId: resortId,
        inchargeEmail: 'incharge@grandpalms.com',
        inchargeName: 'Kavita Menon (Ops Incharge)',
        amount: 45000.0,
        monthYear: 'October 2026',
        paymentMode: 'Bank Transfer / NEFT',
        transactionRef: 'UTR-TEST-INCHARGE-12345',
      );

      expect(payment.id, isNotEmpty);
      expect(payment.amount, 45000.0);
      expect(payment.monthYear, 'October 2026');

      final inchargePayments = store.inchargeSalaryPayments[resortId] ?? [];
      expect(inchargePayments.any((p) => p.transactionRef == 'UTR-TEST-INCHARGE-12345'), isTrue);

      final newExpenses = store.resortExpenses[resortId] ?? [];
      expect(newExpenses.length, initialExpenses + 1);
      final loggedExp = newExpenses.first;
      expect(loggedExp.category, 'staff_salary');
      expect(loggedExp.amount, 45000.0);
      expect(loggedExp.description, contains('Kavita Menon'));

      expect(store.getTotalSalaryExpenses(resortId), initialSalaryTotal + 45000.0);
    });

    test('2. Incharge disburses wage to ground staff and automatically records expense', () {
      const resortId = 'resort-grand-palms';
      final initialExpenses = store.resortExpenses[resortId]?.length ?? 0;
      final initialSalaryTotal = store.getTotalSalaryExpenses(resortId);

      final payment = store.disburseStaffSalary(
        resortId: resortId,
        staffId: 'staff-gp-1',
        staffName: 'Ramesh Kumar',
        roleTitle: 'Head Chef',
        amount: 18000.0,
        monthYear: 'October 2026',
        paymentMode: 'UPI Transfer',
        transactionRef: 'VOUCH-TEST-STAFF-67890',
      );

      expect(payment.id, isNotEmpty);
      expect(payment.amount, 18000.0);
      expect(payment.status, 'paid');

      final staffPayments = store.staffSalaryPayments[resortId] ?? [];
      expect(staffPayments.any((p) => p.transactionRef == 'VOUCH-TEST-STAFF-67890'), isTrue);

      final newExpenses = store.resortExpenses[resortId] ?? [];
      expect(newExpenses.length, initialExpenses + 1);
      final loggedExp = newExpenses.first;
      expect(loggedExp.category, 'staff_salary');
      expect(loggedExp.amount, 18000.0);
      expect(loggedExp.description, contains('Ramesh Kumar'));

      expect(store.getTotalSalaryExpenses(resortId), initialSalaryTotal + 18000.0);
    });

    test('3. Admin requests tier change, Super Admin sends payment details, Admin pays and tier updates', () {
      const resortId = 'resort-pine-valley';

      final req = store.requestTierChange(
        resortId: resortId,
        requestedTier: SubscriptionTier.superTier,
      );

      expect(req.id, isNotEmpty);
      expect(req.resortId, resortId);
      expect(req.requestedTier, SubscriptionTier.superTier);
      expect(req.status, TierRequestStatus.pendingPaymentDetails);

      const paymentInstructions =
          'Transfer 499 to ICICI Bank A/C 009283748291, IFSC ICIC0000092 or UPI resorthub.billing@icici';
      store.sendTierPaymentDetails(
        requestId: req.id,
        paymentInstructions: paymentInstructions,
        customAmount: 499.0,
      );

      final updatedReq = store.tierChangeRequests.firstWhere((r) => r.id == req.id);
      expect(updatedReq.status, TierRequestStatus.awaitingAdminPayment);
      expect(updatedReq.paymentInstructions, paymentInstructions);
      expect(updatedReq.amountDue, 499.0);

      store.confirmTierPayment(
        requestId: req.id,
        adminPaymentRef: 'UTR-ICICI-99281248',
      );

      final completedReq = store.tierChangeRequests.firstWhere((r) => r.id == req.id);
      expect(completedReq.status, TierRequestStatus.completed);
      expect(completedReq.adminPaymentRef, 'UTR-ICICI-99281248');

      final resort = store.resorts[resortId];
      expect(resort?.subscriptionTier, SubscriptionTier.superTier);

      final sub = store.resortSubscriptions[resortId];
      expect(sub?.tier, SubscriptionTier.superTier);

      expect(store.subscriptionPayments.any((p) => p.resortId == resortId && p.amount == 499.0), isTrue);
    });

    test('4. Accountant scope retrieves aggregated revenue, salary expenses, and net profit across all resorts', () {
      final totalSalariesAllResorts = store.getTotalSalaryExpenses();
      expect(totalSalariesAllResorts, isPositive);

      final grandPalmsSalaries = store.getTotalSalaryExpenses('resort-grand-palms');
      expect(grandPalmsSalaries, isPositive);
      expect(totalSalariesAllResorts, greaterThanOrEqualTo(grandPalmsSalaries));

      final report = store.getDashboardReport('resort-grand-palms');
      expect(report.monthRevenue, isNonNegative);
      expect(report.monthExpenses, isNonNegative);
    });
  });
}

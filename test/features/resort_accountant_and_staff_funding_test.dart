import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/models/salary_disbursement.dart';
import 'package:pasala/core/models/user_profile.dart';
import 'package:pasala/core/services/mock_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Resort Accountant & Staff Salary Funding Tests', () {
    late MockDataStore store;

    setUp(() {
      store = MockDataStore.instance;
    });

    test('1. Admin adds dedicated accountant for resort and accountant can log in', () {
      const resortId = 'resort-grand-palms';
      final email = 'accountant.test.${DateTime.now().millisecondsSinceEpoch}@grandpalms.com';
      const password = 'testpassword123';
      const fullName = 'Kishore Sharma (Staff Accountant)';

      final newAcc = store.addAccountantForResort(
        resortId: resortId,
        fullName: fullName,
        email: email,
        password: password,
        phone: '+91 98765 00112',
      );

      expect(newAcc.id, isNotEmpty);
      expect(newAcc.email, email);
      expect(newAcc.fullName, fullName);
      expect(newAcc.role, AppRole.accountant);
      expect(newAcc.resortId, resortId);

      // Verify accountant can be fetched by resort
      final assigned = store.getAssignedAccountantForResort(resortId);
      expect(assigned, isNotNull);

      // Verify login credentials authentication
      final loggedIn = store.login(email, password);
      expect(loggedIn, isNotNull);
      expect(loggedIn?.email, email);
      expect(loggedIn?.role, AppRole.accountant);
      expect(loggedIn?.resortId, resortId);
    });

    test('2. Incharge submits staff salary fund request to Admin', () {
      const resortId = 'resort-pine-valley';
      const inchargeEmail = 'incharge@pinevalley.com';
      const inchargeName = 'Devraj Singh';
      const monthYear = 'November 2026';
      const requestedAmount = 58000.0;
      const staffCount = 4;
      const notes = 'Wages for Chef, 2 Housekeepers, 1 Security Guard';

      final req = store.requestStaffSalaryFunds(
        resortId: resortId,
        inchargeEmail: inchargeEmail,
        inchargeName: inchargeName,
        monthYear: monthYear,
        requestedAmount: requestedAmount,
        staffCount: staffCount,
        notes: notes,
      );

      expect(req.id, isNotEmpty);
      expect(req.resortId, resortId);
      expect(req.inchargeEmail, inchargeEmail);
      expect(req.requestedAmount, requestedAmount);
      expect(req.staffCount, staffCount);
      expect(req.status, StaffFundRequestStatus.pending);

      final requests = store.getStaffSalaryFundRequests(resortId);
      expect(requests.any((r) => r.id == req.id), isTrue);
    });

    test('3. Admin reviews and disburses staff payroll funds with UTR, auto-expensing in ledger', () {
      const resortId = 'resort-highland-mist';
      final initialExpenses = store.resortExpenses[resortId]?.length ?? 0;
      final initialSalaryTotal = store.getTotalSalaryExpenses(resortId);

      // Incharge creates request
      final req = store.requestStaffSalaryFunds(
        resortId: resortId,
        inchargeEmail: 'incharge@highlandmist.com',
        inchargeName: 'Sunita Rao',
        monthYear: 'October 2026',
        requestedAmount: 50000.0,
        staffCount: 3,
        notes: 'Ground operations wages for October cycle',
      );

      expect(req.status, StaffFundRequestStatus.pending);

      // Admin approves and disburses funds
      const paymentMode = 'Bank Transfer / NEFT';
      const utrRef = 'UTR-STAFF-FUND-987654';
      store.approveAndDisburseStaffFunds(
        requestId: req.id,
        fundedAmount: 50000.0,
        paymentMode: paymentMode,
        transactionRef: utrRef,
        adminNotes: 'Approved and transferred to Incharge account.',
      );

      // Verify request is updated
      final updatedReq = store.getStaffSalaryFundRequests(resortId).firstWhere((r) => r.id == req.id);
      expect(updatedReq.status, StaffFundRequestStatus.funded);
      expect(updatedReq.fundedAmount, 50000.0);
      expect(updatedReq.transactionRef, utrRef);
      expect(updatedReq.fundedAt, isNotNull);

      // Verify automatic expense logging
      final newExpenses = store.resortExpenses[resortId] ?? [];
      expect(newExpenses.length, initialExpenses + 1);
      final loggedExp = newExpenses.first;
      expect(loggedExp.category, 'staff_salary');
      expect(loggedExp.amount, 50000.0);
      expect(loggedExp.description, contains('Staff Payroll Funds'));
      expect(loggedExp.description, contains('Sunita Rao'));

      // Verify total salary expenses updated
      expect(store.getTotalSalaryExpenses(resortId), initialSalaryTotal + 50000.0);

      // Verify funded payroll tracking
      expect(store.getTotalFundedStaffPayroll(resortId, 'October 2026'), 50000.0);
      expect(store.getAvailableStaffPayrollFunds(resortId, 'October 2026'), 50000.0);
    });

    test('4. Incharge disburses wage to staff, reducing available funded payroll balance', () {
      const resortId = 'resort-lakeside-eco';

      // Fund request
      final req = store.requestStaffSalaryFunds(
        resortId: resortId,
        inchargeEmail: 'incharge@lakesideeco.com',
        inchargeName: 'Alok Varma',
        monthYear: 'December 2026',
        requestedAmount: 32000.0,
        staffCount: 2,
      );

      store.approveAndDisburseStaffFunds(
        requestId: req.id,
        fundedAmount: 32000.0,
        paymentMode: 'UPI Transfer',
        transactionRef: 'UTR-LAKESIDE-112233',
      );

      expect(store.getAvailableStaffPayrollFunds(resortId, 'December 2026'), 32000.0);

      // Incharge pays staff 1
      store.disburseStaffSalary(
        resortId: resortId,
        staffId: 'staff-ls-1',
        staffName: 'Mohan Lal',
        roleTitle: 'Head Cook',
        amount: 18000.0,
        monthYear: 'December 2026',
        paymentMode: 'UPI Transfer',
        transactionRef: 'VOUCH-MOHAN-11',
      );

      // Available balance should now be 32000 - 18000 = 14000
      expect(store.getAvailableStaffPayrollFunds(resortId, 'December 2026'), 14000.0);

      // Incharge pays staff 2
      store.disburseStaffSalary(
        resortId: resortId,
        staffId: 'staff-ls-2',
        staffName: 'Gita Devi',
        roleTitle: 'Housekeeper',
        amount: 14000.0,
        monthYear: 'December 2026',
        paymentMode: 'Cash Voucher',
        transactionRef: 'VOUCH-GITA-22',
      );

      // Available balance is now 0
      expect(store.getAvailableStaffPayrollFunds(resortId, 'December 2026'), 0.0);
    });

    test('5. Global accountant@resorthub.com can log in and has access to all subscribed resorts', () {
      final user = store.login('accountant@resorthub.com', 'password123');
      expect(user, isNotNull);
      expect(user?.email, 'accountant@resorthub.com');
      expect(user?.role, AppRole.accountant);
      expect(user?.resortId, isNull); // Platform-wide global access

      // Verify they can view platform-wide reports aggregating all resorts
      final platformReport = store.getPlatformAccountantReport();
      expect(platformReport, isNotNull);
      expect(platformReport.monthRevenue, greaterThan(0));

      // Verify they can inspect individual resorts accounts
      for (final resort in store.resorts.values) {
        final resortReport = store.getDashboardReport(resort.id);
        expect(resortReport, isNotNull);
      }
    });
  });
}

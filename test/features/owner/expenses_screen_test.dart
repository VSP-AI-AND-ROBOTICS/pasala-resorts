import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/expense.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/auth_repository.dart';
import 'package:pasala/data/repositories/expense_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/expenses_screen.dart';

class FakeExpenseRepository implements ExpenseRepository {
  final List<Expense> store = [];
  final List<String> deletedIds = [];
  int _idCounter = 0;

  /// Compares dates only, ignoring time-of-day -- see the identical
  /// comment on `FakeFoodSaleRepository._inRange` in
  /// `food_sales_screen_test.dart` for why.
  bool _inRange(DateTime date, DateTime from, DateTime to) {
    final d = DateTime(date.year, date.month, date.day);
    final f = DateTime(from.year, from.month, from.day);
    final t = DateTime(to.year, to.month, to.day);
    return !d.isBefore(f) && !d.isAfter(t);
  }

  @override
  Future<List<Expense>> list({required DateTime from, required DateTime to}) async =>
      store.where((e) => _inRange(e.expenseDate, from, to)).toList();

  @override
  Future<void> create(Expense expense) async {
    store.add(Expense(
      id: 'expense-${_idCounter++}',
      propertyId: expense.propertyId,
      expenseDate: expense.expenseDate,
      category: expense.category,
      description: expense.description,
      amount: expense.amount,
      paidTo: expense.paidTo,
      paymentMethod: expense.paymentMethod,
    ));
  }

  @override
  Future<void> update(String id, Expense expense) async {
    final i = store.indexWhere((e) => e.id == id);
    store[i] = Expense(
      id: id,
      propertyId: expense.propertyId,
      expenseDate: expense.expenseDate,
      category: expense.category,
      description: expense.description,
      amount: expense.amount,
      paidTo: expense.paidTo,
      paymentMethod: expense.paymentMethod,
    );
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    store.removeWhere((e) => e.id == id);
  }
}

const _property = Property(
  id: 'p1',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
);

const _admin = AppUser(
  id: 'admin-1',
  email: 'admin@pasala.test',
  role: UserRole.admin,
  fullName: 'Asha Admin',
);

const _accountant = AppUser(
  id: 'accountant-1',
  email: 'accounts@pasala.test',
  role: UserRole.accountant,
  fullName: 'Anil Accounts',
);

Widget _appFor(
  FakeExpenseRepository repo, {
  AppUser user = _admin,
}) =>
    ProviderScope(
      overrides: [
        expenseRepositoryProvider.overrideWithValue(repo),
        propertiesProvider.overrideWith((ref) async => [_property]),
        currentUserProvider.overrideWith((ref) => Stream.value(user)),
      ],
      child: const MaterialApp(home: ExpensesScreen()),
    );

void main() {
  testWidgets('shows an empty state when no expenses exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeExpenseRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No expenses logged in this period'), findsOneWidget);
  });

  // I7: expenses_admin_write (0027_expenses.sql) only lets admin/super_admin
  // actually write -- an accountant can read the books (expenses_read
  // grants it) but must never see an add/edit/delete control that would
  // just fail against RLS the moment they tapped it.
  testWidgets('an accountant sees no add button and no edit/delete menu', (
    tester,
  ) async {
    final repo = FakeExpenseRepository()
      ..store.add(Expense(
        id: 'e1',
        propertyId: 'p1',
        expenseDate: DateTime.now(),
        category: 'Utilities',
        description: 'Electricity bill',
        amount: 5000,
      ));

    await tester.pumpWidget(_appFor(repo, user: _accountant));
    await tester.pumpAndSettle();

    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  testWidgets('filling the create form and saving adds an expense to the list', (
    tester,
  ) async {
    final repo = FakeExpenseRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('expense-form-category')), 'Utilities');
    await tester.enterText(
      find.byKey(const Key('expense-form-description')), 'Electricity bill');
    await tester.enterText(find.byKey(const Key('expense-form-amount')), '5000');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.store, hasLength(1));
    expect(find.text('Electricity bill'), findsOneWidget);
  });

  testWidgets('confirming delete removes the expense', (tester) async {
    final repo = FakeExpenseRepository()
      ..store.add(Expense(
        id: 'e1',
        propertyId: 'p1',
        expenseDate: DateTime.now(),
        category: 'Utilities',
        description: 'Electricity bill',
        amount: 5000,
      ));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['e1']);
    expect(find.text('Electricity bill'), findsNothing);
  });
}

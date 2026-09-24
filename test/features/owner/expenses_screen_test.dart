import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/data/models/app_user.dart';
import 'package:pasala/data/models/expense.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/expense_repository.dart';
import 'package:pasala/features/owner/expenses_screen.dart';

class _FixedResort extends CurrentResort {
  _FixedResort(this._value);
  final ResortMembership? _value;
  @override
  ResortMembership? build() => _value;
}

class FakeExpenseRepository implements ExpenseRepository {
  final List<Expense> store = [];
  final List<String> deletedIds = [];
  final List<String> listedPropertyIds = [];
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
  Future<List<Expense>> list({
    required String propertyId,
    required DateTime from,
    required DateTime to,
  }) async {
    listedPropertyIds.add(propertyId);
    return store
        .where((e) => e.propertyId == propertyId && _inRange(e.expenseDate, from, to))
        .toList();
  }

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

const _adminM =
    ResortMembership(propertyId: 'p1', resortName: 'Pasala', role: ResortRole.admin);
const _accountantM = ResortMembership(
    propertyId: 'p1', resortName: 'Pasala', role: ResortRole.accountant);

const _admin = AppUser(
  id: 'admin-1',
  email: 'admin@pasala.test',
  memberships: [_adminM],
  fullName: 'Asha Admin',
);

const _accountant = AppUser(
  id: 'accountant-1',
  email: 'accounts@pasala.test',
  memberships: [_accountantM],
  fullName: 'Anil Accounts',
);

Widget _appFor(
  FakeExpenseRepository repo, {
  AppUser user = _admin,
  ResortMembership? resort,
}) =>
    ProviderScope(
      overrides: [
        expenseRepositoryProvider.overrideWithValue(repo),
        currentResortProvider.overrideWith(
            () => _FixedResort(resort ?? user.memberships.first)),
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
    expect(repo.store.single.propertyId, 'p1');
    expect(find.text('Electricity bill'), findsOneWidget);
  });

  // Review Focus #1: an admin with memberships at two resorts must never
  // see resort B's expenses while working in resort A -- RLS alone would
  // let them read both, so the screen must filter by the current resort.
  testWidgets('an expense logged at a different resort never appears here', (
    tester,
  ) async {
    const otherResort = ResortMembership(
        propertyId: 'p2', resortName: 'Other Resort', role: ResortRole.admin);
    final repo = FakeExpenseRepository()
      ..store.add(Expense(
        id: 'e1',
        propertyId: 'p1',
        expenseDate: DateTime.now(),
        category: 'Utilities',
        description: 'Pasala electricity bill',
        amount: 5000,
      ))
      ..store.add(Expense(
        id: 'e2',
        propertyId: 'p2',
        expenseDate: DateTime.now(),
        category: 'Utilities',
        description: 'Other resort electricity bill',
        amount: 7000,
      ));

    await tester.pumpWidget(_appFor(repo, resort: otherResort));
    await tester.pumpAndSettle();

    expect(repo.listedPropertyIds, everyElement('p2'));
    expect(find.text('Other resort electricity bill'), findsOneWidget);
    expect(find.text('Pasala electricity bill'), findsNothing);
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

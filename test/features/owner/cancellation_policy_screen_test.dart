import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/models/refund_rule.dart';
import 'package:pasala/data/repositories/refund_rule_repository.dart';
import 'package:pasala/features/owner/cancellation_policy_screen.dart';

class FakeRefundRuleRepository implements RefundRuleRepository {
  final List<RefundRule> store = [];
  final List<String> deletedIds = [];
  int _idCounter = 0;

  @override
  Future<List<RefundRule>> list(String propertyId) async =>
      store.where((r) => r.propertyId == propertyId).toList()
        ..sort((a, b) => a.minDaysBefore.compareTo(b.minDaysBefore));

  @override
  Future<void> create(RefundRule rule) async {
    store.add(RefundRule(
      id: 'rule-${_idCounter++}',
      propertyId: rule.propertyId,
      minDaysBefore: rule.minDaysBefore,
      refundPct: rule.refundPct,
    ));
  }

  @override
  Future<void> update(String id, RefundRule rule) async {
    final i = store.indexWhere((r) => r.id == id);
    store[i] = RefundRule(
      id: id,
      propertyId: rule.propertyId,
      minDaysBefore: rule.minDaysBefore,
      refundPct: rule.refundPct,
    );
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    store.removeWhere((r) => r.id == id);
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

Widget _appFor(FakeRefundRuleRepository repo) => ProviderScope(
      overrides: [refundRuleRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: CancellationPolicyScreen(property: _property)),
    );

void main() {
  testWidgets('shows an empty state when no tiers exist yet', (tester) async {
    await tester.pumpWidget(_appFor(FakeRefundRuleRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No refund tiers yet'), findsOneWidget);
  });

  testWidgets('filling the create form and saving adds a tier', (tester) async {
    final repo = FakeRefundRuleRepository();
    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('refund-rule-min-days-field')), '7');
    await tester.enterText(find.byKey(const Key('refund-rule-pct-field')), '50');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.store, hasLength(1));
    expect(find.text('7+ days before check-in'), findsOneWidget);
    expect(find.text('50% refunded'), findsOneWidget);
  });

  testWidgets('confirming delete removes the tier', (tester) async {
    final repo = FakeRefundRuleRepository()
      ..store.add(const RefundRule(id: 'r1', propertyId: 'p1', minDaysBefore: 7, refundPct: 50));

    await tester.pumpWidget(_appFor(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, ['r1']);
    expect(find.text('7+ days before check-in'), findsNothing);
  });
}

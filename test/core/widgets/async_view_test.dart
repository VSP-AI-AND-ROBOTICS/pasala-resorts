import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/widgets/async_view.dart';

void main() {
  Widget host(AsyncValue<List<String>> value, {Widget Function()? empty}) =>
      MaterialApp(
        home: Scaffold(
          body: AsyncView<List<String>>(
            value: value,
            empty: empty,
            data: (items) => Text('items:${items.length}'),
          ),
        ),
      );

  testWidgets('loading renders a progress indicator', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.loading()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('error renders the failure message, not the raw error', (tester) async {
    await tester.pumpWidget(host(
      AsyncValue.error(
        const UnknownFailure('permission denied for table reservations'),
        StackTrace.empty,
      ),
    ));
    await tester.pump();
    expect(find.textContaining('reservations'), findsNothing);
  });

  testWidgets('empty builder is used for an empty list', (tester) async {
    await tester.pumpWidget(host(
      const AsyncValue.data(<String>[]),
      empty: () => const Text('nothing here'),
    ));
    expect(find.text('nothing here'), findsOneWidget);
    expect(find.text('items:0'), findsNothing);
  });

  testWidgets('data builder is used for a non-empty list', (tester) async {
    await tester.pumpWidget(host(const AsyncValue.data(<String>['a', 'b'])));
    expect(find.text('items:2'), findsOneWidget);
  });
}

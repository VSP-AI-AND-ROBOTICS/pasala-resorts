import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pasala/core/router.dart';

void main() {
  testWidgets(
      'fadeSlidePage wraps the destination in a fade and slide transition',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/a',
      routes: [
        GoRoute(
          path: '/a',
          pageBuilder: (_, state) => fadeSlidePage(const Text('Screen A'), state),
        ),
        GoRoute(
          path: '/b',
          pageBuilder: (_, state) => fadeSlidePage(const Text('Screen B'), state),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('Screen A'), findsOneWidget);

    router.go('/b');
    await tester.pump();

    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);

    await tester.pumpAndSettle();
    expect(find.text('Screen B'), findsOneWidget);
    expect(find.text('Screen A'), findsNothing);
  });
}

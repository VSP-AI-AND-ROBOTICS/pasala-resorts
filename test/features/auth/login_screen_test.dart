import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/brand_mark.dart';
import 'package:pasala/features/auth/login_screen.dart';

void main() {
  testWidgets('shows email, password, and a sign-in button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.byKey(const Key('login-email')), findsOneWidget);
    expect(find.byKey(const Key('login-password')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('rejects an empty email', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('shows the ResortHub name, not the Pasala logo or name',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('ResortHub'), findsOneWidget);
    expect(find.text('Pasala Resorts'), findsNothing);
    expect(find.byType(BrandMark), findsNothing);
  });
}

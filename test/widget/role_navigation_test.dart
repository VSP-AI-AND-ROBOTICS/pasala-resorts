import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/auth/login_page.dart';

void main() {
  testWidgets('ResortHubApp builds cleanly and renders initial screens', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pump();

    // Verify login screen renders by default
    expect(find.textContaining('ResortHub'), findsWidgets);
    expect(find.textContaining('Sign in'), findsWidgets);
  });
}

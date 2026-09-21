import 'package:flutter_test/flutter_test.dart';
import 'package:resorthub/main.dart';

void main() {
  testWidgets('ResortHubApp builds cleanly and renders initial screens', (WidgetTester tester) async {
    await tester.pumpWidget(const ResortHubApp());
    // Use pump with finite duration instead of pumpAndSettle to avoid waiting for network images
    await tester.pump(const Duration(milliseconds: 500));

    // Verify login screen renders by default
    expect(find.textContaining('ResortHub'), findsWidgets);
    expect(find.textContaining('Sign in'), findsWidgets);
  });
}

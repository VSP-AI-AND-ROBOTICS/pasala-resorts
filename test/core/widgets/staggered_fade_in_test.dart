import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/widgets/staggered_fade_in.dart';

void main() {
  testWidgets('renders its child fully visible once settled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: StaggeredFadeIn(index: 3, child: Text('item')),
    ));

    await tester.pumpAndSettle();

    expect(find.text('item'), findsOneWidget);
    final opacity = tester.widget<Opacity>(find.byType(Opacity));
    expect(opacity.opacity, 1.0);
  });

  testWidgets('a later index takes longer to finish than an earlier one', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        StaggeredFadeIn(index: 0, child: Text('first')),
        StaggeredFadeIn(index: 5, child: Text('second')),
      ]),
    ));

    await tester.pump(const Duration(milliseconds: 260));

    final opacities = tester.widgetList<Opacity>(find.byType(Opacity)).toList();
    expect(opacities[0].opacity, 1.0);
    expect(opacities[1].opacity, lessThan(1.0));
  });
}

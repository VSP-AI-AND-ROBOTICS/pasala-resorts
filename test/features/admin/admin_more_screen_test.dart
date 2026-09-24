import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/admin_more_screen.dart';

void main() {
  testWidgets(
      'lists every management screen the old Admin home grid used to hold',
      (tester) async {
    // GridView.builder virtualizes offscreen children -- without a tall
    // enough surface, the later tiles simply aren't in the tree yet.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AdminMoreScreen()));
    await tester.pumpAndSettle();

    for (final title in const [
      'Properties',
      'Financial Dashboard',
      'Outbox',
      'Staff shifts',
      'Leave requests',
      'Attendance',
      'Tasks',
      'Service requests',
    ]) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });
}

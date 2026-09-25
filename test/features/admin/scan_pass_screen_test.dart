import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pasala/features/admin/scan_pass_screen.dart';

void main() {
  late String? result;
  late int returns;

  Widget app() {
    result = 'unset';
    returns = 0;
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, _) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final code = await context.push<String>('/scan');
                  returns++;
                  result = code;
                },
                child: const Text('OPEN SCANNER'),
              ),
            ),
          ),
        ),
        GoRoute(path: '/scan', builder: (_, _) => const ScanPassScreen()),
      ],
    );
    return ProviderScope(
      overrides: [
        // No camera under flutter test: a button stands in for it. A real
        // camera reports the same code on many frames, so it fires twice.
        passScannerProvider.overrideWithValue(
          (context, onCode) => Center(
            child: TextButton(
              key: const Key('fake-camera'),
              onPressed: () {
                onCode('rh1.first');
                onCode('rh1.second');
              },
              child: const Text('READ'),
            ),
          ),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openScanner(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('OPEN SCANNER'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the camera, a hint and a way to type the code instead',
      (tester) async {
    await openScanner(tester);

    expect(find.text('Scan pass'), findsOneWidget);
    expect(find.byKey(const Key('fake-camera')), findsOneWidget);
    expect(find.text("Point the camera at the guest's check-in QR."), findsOneWidget);
    expect(find.text('Enter code instead'), findsOneWidget);
  });

  // Review Focus 1.
  testWidgets('the first code read leaves the screen with that code, once',
      (tester) async {
    await openScanner(tester);

    await tester.tap(find.byKey(const Key('fake-camera')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result, 'rh1.first');
    expect(returns, 1);
    expect(find.text('OPEN SCANNER'), findsOneWidget);
  });

  testWidgets('Enter code instead returns with no code', (tester) async {
    await openScanner(tester);

    await tester.tap(find.byKey(const Key('scan-enter-code')));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(returns, 1);
    expect(find.text('OPEN SCANNER'), findsOneWidget);
  });

  group('cameraErrorMessage', () {
    test('a denied permission says how to turn it on', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.permissionDenied),
          'Camera access is off. Allow the camera in your browser or phone '
          'settings, or enter the code instead.');
    });

    test('a device without a camera says so', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.unsupported),
          'This device has no camera the app can use. Enter the code instead.');
    });

    test('anything else offers typing the code', () {
      expect(cameraErrorMessage(MobileScannerErrorCode.genericError),
          'The camera could not start. Enter the code instead.');
    });
  });
}

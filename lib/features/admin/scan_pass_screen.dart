import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/tokens.dart';

/// Builds the live camera view. [onCode] gets the raw text of every QR
/// code the camera reads. Tests override [passScannerProvider] with a
/// stand-in, because there is no camera under `flutter test`.
typedef PassScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

final passScannerProvider = Provider<PassScannerBuilder>(
  (ref) => (context, onCode) => CameraPassScanner(onCode: onCode),
);

/// What reception reads when the camera cannot start. Every message ends
/// with the way out: typing the code on the check-in screen.
String cameraErrorMessage(MobileScannerErrorCode code) => switch (code) {
      MobileScannerErrorCode.permissionDenied =>
        'Camera access is off. Allow the camera in your browser or phone '
            'settings, or enter the code instead.',
      MobileScannerErrorCode.unsupported =>
        'This device has no camera the app can use. Enter the code instead.',
      _ => 'The camera could not start. Enter the code instead.',
    };

/// `/admin/check-in/scan` -- the camera. Pops with the raw text of the
/// first QR code it reads (the check-in screen verifies it), or with null
/// when reception taps "Enter code instead".
class ScanPassScreen extends ConsumerStatefulWidget {
  const ScanPassScreen({super.key});

  @override
  ConsumerState<ScanPassScreen> createState() => _ScanPassScreenState();
}

class _ScanPassScreenState extends ConsumerState<ScanPassScreen> {
  bool _done = false;

  void _onCode(String code) {
    // The camera keeps reporting the same code frame after frame; only the
    // first one leaves the screen.
    if (_done || !mounted) return;
    _done = true;
    context.pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(passScannerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pass')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          scanner(context, _onCode),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                ),
              ),
            ),
          ),
          Positioned(
            left: Spacing.md,
            right: Spacing.md,
            bottom: Spacing.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(Spacing.sm),
                    child: Text(
                      "Point the camera at the guest's check-in QR.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                FilledButton.tonal(
                  key: const Key('scan-enter-code'),
                  onPressed: () {
                    if (_done) return;
                    _done = true;
                    context.pop();
                  },
                  child: const Text('Enter code instead'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mobile_scanner camera, reading QR codes only.
class CameraPassScanner extends StatefulWidget {
  const CameraPassScanner({super.key, required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<CameraPassScanner> createState() => _CameraPassScannerState();
}

class _CameraPassScannerState extends State<CameraPassScanner> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value != null && value.isNotEmpty) {
              widget.onCode(value);
              return;
            }
          }
        },
        errorBuilder: (context, error) => ColoredBox(
          color: Colors.black,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.no_photography_outlined,
                      color: Colors.white, size: 48),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    cameraErrorMessage(error.errorCode),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

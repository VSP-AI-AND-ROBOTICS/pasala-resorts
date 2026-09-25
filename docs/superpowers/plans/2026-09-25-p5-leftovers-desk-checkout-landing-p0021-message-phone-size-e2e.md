# P5 Leftovers (desk checkout landing, P0021 message, phone-size E2E) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After a desk checkout, reception lands back on its own check-out list with a success banner and a Download invoice action. P0021 stays readable all the way to the screen. The Playwright persona specs pass at desktop and at phone (Pixel 7) size.

**Architecture:** Flutter only, no database work. `CheckoutScreen` in desk mode goes to `/admin/check-out?checkedOut=<id>`. `ReceptionCheckoutScreen` reads that query parameter and shows a `DeskCheckoutBanner`. The banner's Download invoice calls a small seam, `deskInvoiceDownloadProvider`. That seam is `null` (button hidden) until the final integration task binds it to P2's invoice PDF. The Playwright config gains a `phone` project (full `devices['Pixel 7']`). `e2e/support/nav.ts` gains `useBottomNav`, `reveal` and `revealAndClick`, which specs use for content below a phone's fold.

**Tech Stack:** Flutter 3 / Dart, Riverpod 3, go_router, flutter_test; Playwright 1.63 (TypeScript, Chromium) against the Flutter web E2E build and the local Supabase stack.

**Spec:** `docs/superpowers/specs/2026-09-25-p5-leftovers-desk-checkout-landing-p0021-message-phone-size-e2e-design.md`

## Global Constraints

- No migration, SQL function, pgTAP file or error code: P5's reserved 0054 slot stays unused.
- The success message lives in the URL: `/admin/check-out?checkedOut=<reservationId>` (query key `checkedOut`, constant `checkedOutParam`).
- Banner copy is exact: title "Guest checked out", line "Booking `<first 8 chars of id>` is settled.", button "Download invoice" (busy: "Preparing invoice…"), dismiss tooltip "Dismiss".
- `typedef DeskInvoiceDownload = Future<void> Function(BuildContext context, WidgetRef ref, String reservationId);`, and `deskInvoiceDownloadProvider` is `Provider<DeskInvoiceDownload?>`, `null` until P2 is bound.
- The guest's self-checkout still ends on `/my-stay/invoice/<id>`. Only the desk path changes.
- Errors on screen go through `FailureView.messageFor(mapPostgrestError(e))`, so raw server text never shows.
- P0021 copy stays "That belongs to a different resort." (`ResortMismatch`, landed in `8f46008`).
- Playwright projects: `desktop` (`devices['Desktop Chrome']`, 1280x800) and `phone` (`devices['Pixel 7']`: 412x839, DPR 2.625, isMobile, hasTouch, Android UA). `workers: 1`. No screenshot or pixel assertions.
- Helpers, not screenshots: do not drop `isMobile`/`hasTouch` from the phone project to get past a failure. Fix the helper instead.
- `flutter analyze` baseline: exactly 2 infos in `service_request_screen.dart`. Never run `dart format` on whole directories or pre-existing files you did not change. Revert SDK-only `pubspec.lock` bumps.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.
- The E2E suite shares one local database with other worktrees. Run Playwright only when the orchestrator says the stack is free, and never run `supabase db reset`.

## Review Focus

1. **A second desk checkout while the banner is still showing.** Reception checks out guest A, leaves the banner up, then checks out guest B. The banner must switch to B's booking id and lose A's busy state, and Download must fetch B's invoice. Pinned in Task 2 ("a second checkout replaces the banner and resets it").
2. **Dismissing while the invoice is still being prepared.** A slow PDF build is followed by a tap on the X. There must be no `setState` after dispose and no stray snackbar when the download later fails. Pinned in Task 2 ("dismissing while the invoice is still being prepared is safe").
3. **An odd `checkedOut` value in the URL.** Someone edits or pastes the URL: an id shorter than 8 characters, a blank value, or characters that need encoding. The short id must be shown whole (no `RangeError`), a blank value must mean no banner, and `deskCheckoutDoneLocation` must encode the id. Pinned in Task 2 ("a short id in the URL is shown whole", "no banner … blank", "deskCheckoutDoneLocation encodes the id").
4. **Phone layout: a target *above* the viewport after an earlier `reveal` scrolled down.** Example: the platform console's tier trigger after revealing the third card. `reveal` must scroll back up, not only down. This is built into `reveal` (Task 3), which uses the target's box to pick a direction and searches upwards after `maxScrolls`. It is exercised by the platform tier-filter test on the `phone` project (Task 4 run).
5. **Phone layout: a target hidden behind the bottom navigation bar.** A button near the bottom edge is "visible" to Playwright, but a click lands on the NavigationBar. `reveal` treats the bottom 80px as out of view on a narrow layout (Task 3). This is exercised by the guest booking flow's Pay button and the owner hub tiles on the `phone` project (Task 4 run).

---

## File Structure

| File | Task | Responsibility |
|---|---|---|
| `test/core/widgets/failure_view_test.dart` (modify) | 1 | P0021 from server to screen |
| `lib/features/admin/desk_invoice.dart` (create) | 2, bound in 4 | `DeskInvoiceDownload` seam + provider |
| `lib/features/admin/desk_checkout_banner.dart` (create) | 2 | success banner + Download invoice |
| `lib/features/admin/reception_checkout_screen.dart` (modify) | 2 | `checkedOutParam`, `deskCheckoutDoneLocation`, banner above the list |
| `lib/core/router.dart` (modify) | 2 | pass the query parameter to the list |
| `lib/features/stay/checkout_screen.dart` (modify) | 2 | desk success goes to the list |
| `test/features/admin/reception_checkout_screen_test.dart` (modify) | 2 | banner tests |
| `test/features/stay/checkout_screen_test.dart` (modify) | 2 | desk landing tests |
| `test/core/router_test.dart` (modify) | 2 | URL-alone build of the list with banner |
| `e2e/playwright.config.ts` (modify) | 3 | `desktop` + `phone` projects |
| `e2e/support/nav.ts`, `e2e/support/index.ts` (modify) | 3 | `WIDE_BREAKPOINT`, `isNarrow`, `useBottomNav`, `clickTab`, `reveal`, `revealAndClick` |
| `e2e/tests/*.spec.ts` (modify) | 3, 4 | phone-safe navigation; desk landing E2E (4) |
| `README.md` (modify) | 3 | running each project |
| `test/features/admin/desk_invoice_test.dart` (create) | 4 | the provider is bound |
| `e2e/REPORT.md` (modify) | 4 | results per project |

Tracks: Tasks 1, 2 and 3 touch disjoint files and can run in parallel. Task 4 (integration) runs after all three **and after P2 is merged**.

---

### Task 1: P0021 reaches the screen as readable copy

The mapping already exists (`lib/core/errors.dart`: `'P0021' => const ResortMismatch()`, from commit `8f46008`), and `test/core/errors_test.dart` checks it. This task pins the whole chain through `FailureView`, which every `AsyncValue.error` branch in the app renders. Then no future refactor of `errors.dart` or `FailureView.messageFor` can put `resort_mismatch` back on a screen.

**Files:**
- Modify: `test/core/widgets/failure_view_test.dart`

**Interfaces:**
- Consumes: `mapPostgrestError(Object) -> BookingFailure`, `ResortMismatch`, `FailureView({required Object error, VoidCallback? onRetry})`, `FailureView.messageFor(Object) -> String` (all existing).
- Produces: nothing new.

- [ ] **Step 1: Write the test**

In `test/core/widgets/failure_view_test.dart`, add this import next to the other package imports:

```dart
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
```

and add this test inside `main()`, after the test `falls back to a generic message for a non-BookingFailure error`:

```dart
  // P0021: the resort-consistency trigger (0043_resort_tenancy.sql) sends
  // only the code word `resort_mismatch`. From the server error, through
  // mapPostgrestError, to what FailureView paints: readable copy only.
  testWidgets('P0021 from the server reaches the screen as readable copy',
      (tester) async {
    final failure = mapPostgrestError(
        PostgrestException(message: 'resort_mismatch', code: 'P0021'));
    await tester.pumpWidget(MaterialApp(home: FailureView(error: failure)));

    expect(find.text('That belongs to a different resort.'), findsOneWidget);
    expect(find.textContaining('resort_mismatch'), findsNothing);
    expect(FailureView.messageFor(failure),
        'That belongs to a different resort.');
  });
```

- [ ] **Step 2: Run it**

Run: `flutter test test/core/widgets/failure_view_test.dart`
Expected: PASS. The mapping landed in `8f46008`; this test pins it.

- [ ] **Step 3: Prove the test bites**

Temporarily change `lib/core/errors.dart`'s `'P0021' => const ResortMismatch(),` to `'P0021' => InvalidState(message),` and run the same command.
Expected: FAIL with `Expected: exactly one matching candidate` for "That belongs to a different resort.".
Revert the change: `git checkout lib/core/errors.dart`. Run again. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/core/widgets/failure_view_test.dart
git commit -m "test(errors): pin P0021 readable copy through FailureView

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Desk checkout lands on the check-out list with a success banner

**Files:**
- Create: `lib/features/admin/desk_invoice.dart`
- Create: `lib/features/admin/desk_checkout_banner.dart`
- Modify: `lib/features/admin/reception_checkout_screen.dart`
- Modify: `lib/core/router.dart` (the `/admin/check-out` `GoRoute`, around line 628)
- Modify: `lib/features/stay/checkout_screen.dart` (`_checkout`, around lines 88-100)
- Test: `test/features/admin/reception_checkout_screen_test.dart`, `test/features/stay/checkout_screen_test.dart`, `test/core/router_test.dart`

**Interfaces:**
- Consumes: `checkedInProvider` (`FutureProvider.autoDispose.family<List<Reservation>, String>`, `lib/data/repositories/stay_repository.dart`), `currentResortProvider`, `AsyncView`, `EmptyState`, `FailureView.messageFor`, `mapPostgrestError`, `Spacing` (from `lib/core/theme/tokens.dart`).
- Produces:
  - `lib/features/admin/desk_invoice.dart`: `typedef DeskInvoiceDownload = Future<void> Function(BuildContext context, WidgetRef ref, String reservationId);` and `final deskInvoiceDownloadProvider = Provider<DeskInvoiceDownload?>((ref) => null);`. Task 4 binds it.
  - `lib/features/admin/desk_checkout_banner.dart`: `class DeskCheckoutBanner extends ConsumerStatefulWidget` with `const DeskCheckoutBanner({Key? key, required String reservationId, required VoidCallback onDismiss})`. Keys: card `Key('desk-checkout-done')`, button `Key('desk-invoice-download')`. Also `String shortBookingId(String id)`.
  - `lib/features/admin/reception_checkout_screen.dart`: `const checkedOutParam = 'checkedOut';`, `String deskCheckoutDoneLocation(String reservationId)`, and `ReceptionCheckoutScreen({Key? key, String? checkedOutId})`.

- [ ] **Step 1: Write the failing banner tests**

In `test/features/admin/reception_checkout_screen_test.dart`, add these imports:

```dart
import 'dart:async';

import 'package:pasala/features/admin/desk_invoice.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
```

After the existing `_appFor` function, add:

```dart
typedef _Harness = ({Widget app, GoRouter router});

/// The check-out list at [location] (e.g. `/admin/check-out?checkedOut=r1`),
/// routed like `router.dart` does, with [download] as the invoice seam.
_Harness _appAt(
  String location, {
  List<Reservation> guests = const [],
  DeskInvoiceDownload? download,
}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/admin/check-out',
        builder: (_, state) => ReceptionCheckoutScreen(
          checkedOutId: state.uri.queryParameters[checkedOutParam],
        ),
      ),
    ],
  );
  return (
    app: ProviderScope(
      overrides: [
        checkedInProvider.overrideWith((ref, propertyId) async => guests),
        currentResortProvider.overrideWith(_FixedResort.new),
        deskInvoiceDownloadProvider.overrideWithValue(download),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
    router: router,
  );
}

Future<void> _noop(BuildContext _, WidgetRef _, String _) async {}
```

At the end of `main()`, add:

```dart
  group('after a desk checkout', () {
    const id = 'abcdef12-3456-4000-8000-000000000001';
    const second = '99887766-3456-4000-8000-000000000002';
    final downloadButton = find.byKey(const Key('desk-invoice-download'));

    test('deskCheckoutDoneLocation encodes the id', () {
      expect(deskCheckoutDoneLocation('r1'), '/admin/check-out?checkedOut=r1');
      expect(deskCheckoutDoneLocation('a&b'),
          '/admin/check-out?checkedOut=a%26b');
    });

    testWidgets('no banner without a checked-out booking, or with a blank one',
        (tester) async {
      for (final location in [
        '/admin/check-out',
        '/admin/check-out?checkedOut=',
        '/admin/check-out?checkedOut=%20',
      ]) {
        final h = _appAt(location, download: _noop);
        addTearDown(h.router.dispose);
        await tester.pumpWidget(h.app);
        await tester.pumpAndSettle();
        expect(find.text('Guest checked out'), findsNothing, reason: location);
      }
    });

    testWidgets('shows the success banner above the remaining guests',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          guests: [_checkedIn('r2', customerName: 'Meera Nair')],
          download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('desk-checkout-done')), findsOneWidget);
      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('Booking abcdef12 is settled.'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);
      expect(find.text('Meera Nair'), findsOneWidget);
    });

    testWidgets('shows above the empty state when the last guest has left',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('No guests currently checked in'), findsOneWidget);
    });

    testWidgets('Download invoice passes the booking id once and shows progress',
        (tester) async {
      final calls = <String>[];
      final pending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, reservationId) {
        calls.add(reservationId);
        return pending.future;
      });
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      expect(find.text('Preparing invoice…'), findsOneWidget);
      expect(tester.widget<TextButton>(downloadButton).enabled, isFalse);

      await tester.tap(downloadButton, warnIfMissed: false);
      await tester.pump();
      expect(calls, [id]);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Download invoice'), findsOneWidget);
      expect(tester.widget<TextButton>(downloadButton).enabled, isTrue);
    });

    testWidgets('without the invoice PDF feature there is no download button',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id');
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsOneWidget);
      expect(downloadButton, findsNothing);
    });

    testWidgets('a refused download shows readable copy and keeps the banner',
        (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) async => throw PostgrestException(
              message: 'resort_mismatch', code: 'P0021'));
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(find.text('That belongs to a different resort.'), findsOneWidget);
      expect(find.textContaining('resort_mismatch'), findsNothing);
      expect(find.text('Guest checked out'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);
    });

    testWidgets('any other failure shows the generic message', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) async =>
              throw StateError('printing plugin exploded'));
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(find.textContaining('exploded'), findsNothing);
    });

    testWidgets('Dismiss clears the banner and the URL', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=$id', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('Guest checked out'), findsNothing);
      expect(h.router.routerDelegate.currentConfiguration.uri.toString(),
          '/admin/check-out');
    });

    // Review Focus 1.
    testWidgets('a second checkout replaces the banner and resets it',
        (tester) async {
      final calls = <String>[];
      final firstPending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, reservationId) {
        calls.add(reservationId);
        return calls.length == 1 ? firstPending.future : Future.value();
      });
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      expect(find.text('Preparing invoice…'), findsOneWidget);

      h.router.go(deskCheckoutDoneLocation(second));
      await tester.pumpAndSettle();
      expect(find.text('Booking 99887766 is settled.'), findsOneWidget);
      expect(find.text('Download invoice'), findsOneWidget);

      await tester.tap(downloadButton);
      await tester.pumpAndSettle();
      expect(calls, [id, second]);

      firstPending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // Review Focus 2.
    testWidgets('dismissing while the invoice is still being prepared is safe',
        (tester) async {
      final pending = Completer<void>();
      final h = _appAt('/admin/check-out?checkedOut=$id',
          download: (_, _, _) => pending.future);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      await tester.tap(downloadButton);
      await tester.pump();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pumpAndSettle();

      pending.completeError(StateError('late failure'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Something went wrong.'), findsNothing);
      expect(find.text('Guest checked out'), findsNothing);
    });

    // Review Focus 3.
    testWidgets('a short id in the URL is shown whole', (tester) async {
      final h = _appAt('/admin/check-out?checkedOut=abc', download: _noop);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();

      expect(find.text('Booking abc is settled.'), findsOneWidget);
    });
  });
```

- [ ] **Step 2: Run the banner tests to verify they fail**

Run: `flutter test test/features/admin/reception_checkout_screen_test.dart`
Expected: FAIL to compile: `Target of URI doesn't exist: 'package:pasala/features/admin/desk_invoice.dart'`, and `checkedOutParam`, `deskCheckoutDoneLocation` and `checkedOutId` are undefined.

- [ ] **Step 3: Create the seam**

Create `lib/features/admin/desk_invoice.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saves one booking's invoice PDF for reception, after a desk checkout.
///
/// Gets the check-out banner's own [context] and [ref] so that the binding
/// below can call the invoice PDF entry point (P2) with whatever it needs.
typedef DeskInvoiceDownload = Future<void> Function(
    BuildContext context, WidgetRef ref, String reservationId);

/// `null` until the invoice PDF feature (P2) is bound here. The check-out
/// banner hides its Download invoice button while it is. A provider, like
/// `csvDownloaderProvider`, so widget tests can capture the call.
final deskInvoiceDownloadProvider =
    Provider<DeskInvoiceDownload?>((ref) => null);
```

- [ ] **Step 4: Create the banner**

Create `lib/features/admin/desk_checkout_banner.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import 'desk_invoice.dart';

/// The first 8 characters of a reservation id, the "Booking abcd1234" form
/// `FinalInvoiceScreen` uses. A shorter id (a hand-edited URL) is shown whole.
String shortBookingId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// The success message on reception's check-out list after a desk checkout
/// (`/admin/check-out?checkedOut=<id>`), with the booking's invoice PDF one
/// tap away. It lives in the URL, so a reload keeps it. It goes when
/// dismissed, when another guest is checked out, or when reception leaves
/// the list.
class DeskCheckoutBanner extends ConsumerStatefulWidget {
  const DeskCheckoutBanner({
    super.key,
    required this.reservationId,
    required this.onDismiss,
  });

  final String reservationId;
  final VoidCallback onDismiss;

  @override
  ConsumerState<DeskCheckoutBanner> createState() => _DeskCheckoutBannerState();
}

class _DeskCheckoutBannerState extends ConsumerState<DeskCheckoutBanner> {
  bool _busy = false;

  Future<void> _download(DeskInvoiceDownload download) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await download(context, ref, widget.reservationId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(FailureView.messageFor(mapPostgrestError(e)))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final download = ref.watch(deskInvoiceDownloadProvider);
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onPrimaryContainer;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        key: const Key('desk-checkout-done'),
        color: theme.colorScheme.primaryContainer,
        margin: const EdgeInsets.fromLTRB(Spacing.md, Spacing.md, Spacing.md, 0),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.sm, Spacing.xs, Spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Spacing.sm),
                child: Icon(Icons.check_circle_outline, color: onContainer),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),
                    Text(
                      'Guest checked out',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: onContainer),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      'Booking ${shortBookingId(widget.reservationId)} is settled.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: onContainer),
                    ),
                    if (download != null)
                      TextButton.icon(
                        key: const Key('desk-invoice-download'),
                        onPressed: _busy ? null : () => _download(download),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(
                            _busy ? 'Preparing invoice…' : 'Download invoice'),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss',
                icon: Icon(Icons.close, color: onContainer),
                onPressed: widget.onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Show it on the check-out list**

In `lib/features/admin/reception_checkout_screen.dart`:

Add the import `import 'desk_checkout_banner.dart';` after the `stay_repository.dart` import.

Replace the class doc's last paragraph and the class header:

```dart
/// arrow). A successful checkout refetches this list itself.
class ReceptionCheckoutScreen extends ConsumerWidget {
  const ReceptionCheckoutScreen({super.key});
```

with

```dart
/// arrow). A successful checkout refetches this list itself.
///
/// A successful desk checkout comes back here as
/// `/admin/check-out?checkedOut=<id>` ([deskCheckoutDoneLocation]), which
/// shows [DeskCheckoutBanner] above the list: the success message and the
/// invoice download. It is in the URL so a reload keeps it.
class ReceptionCheckoutScreen extends ConsumerWidget {
  const ReceptionCheckoutScreen({super.key, this.checkedOutId});

  /// The booking a desk checkout just settled, from [checkedOutParam].
  /// Blank means none.
  final String? checkedOutId;
```

Above the class doc comment (after the imports), add:

```dart
/// The query parameter a desk checkout adds to `/admin/check-out`.
const checkedOutParam = 'checkedOut';

/// Where a successful desk checkout of [reservationId] lands:
/// `/admin/check-out?checkedOut=<id>`, URL-encoded.
String deskCheckoutDoneLocation(String reservationId) => Uri(
      path: '/admin/check-out',
      queryParameters: {checkedOutParam: reservationId},
    ).toString();
```

In `build`, replace

```dart
    return Scaffold(
      appBar: AppBar(title: const Text('Check-Out')),
      body: AsyncView(
```

with

```dart
    final done = checkedOutId?.trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Check-Out')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (done.isNotEmpty)
            DeskCheckoutBanner(
              // A new checkout is a new banner: no busy state carried over.
              key: ValueKey(done),
              reservationId: done,
              onDismiss: () => context.go('/admin/check-out'),
            ),
          Expanded(
            child: AsyncView(
```

and close the new widgets at the end of `build`. Replace the method's tail

```dart
          },
        ),
      ),
    );
  }
}
```

with

```dart
          },
        ),
            ),
          ),
        ],
      ),
    );
  }
}
```

Then run `dart format lib/features/admin/reception_checkout_screen.dart lib/features/admin/desk_checkout_banner.dart lib/features/admin/desk_invoice.dart` (only these files) to fix the indentation of the re-nested `AsyncView`.

- [ ] **Step 6: Run the banner tests to verify they pass**

Run: `flutter test test/features/admin/reception_checkout_screen_test.dart`
Expected: PASS (the 6 existing tests and the 12 new ones).

- [ ] **Step 7: Write the failing desk-landing tests**

In `test/features/stay/checkout_screen_test.dart`, `_pump`'s `GoRouter.routes`, after the `/admin/check-out/:reservationId` route, add:

```dart
      GoRoute(
          path: '/admin/check-out',
          builder: (_, state) =>
              Text('CHECK-OUT LIST ${state.uri.queryParameters['checkedOut']}')),
```

In the test `records the chosen method and the trimmed reference, and never calls the gateway`, replace

```dart
      expect(gateway.charges, isEmpty);
      expect(find.text('INVOICE r1'), findsOneWidget);
```

with

```dart
      expect(gateway.charges, isEmpty);
      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
```

Replace the comment and assertion in the refetch test. Change

```dart
    // The desk checkout used to be pushed from the check-out list, which
    // refetched these on return; it is now reached by URL (so a reload
    // keeps it), and a successful checkout goes on to the invoice, so the
    // screen refetches what checkout_booking changed itself.
```

to

```dart
    // The desk checkout used to be pushed from the check-out list, which
    // refetched these on return; it is now reached by URL (so a reload
    // keeps it), and a successful checkout goes back to the list by URL
    // too, so the screen refetches what checkout_booking changed itself.
```

and in that test replace

```dart
      expect(find.text('INVOICE r1'), findsOneWidget);
      expect(board.boardCalls.length, greaterThan(boardBefore));
```

with

```dart
      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
      expect(board.boardCalls.length, greaterThan(boardBefore));
```

Add this test to the `desk checkout` group, after `a desk checkout refetches the finance figures`:

```dart
    testWidgets('a desk checkout lands back on the check-out list, never the guest invoice',
        (tester) async {
      await _pump(tester, extra: _desk, stay: _FakeStayRepository());

      await tester.tap(find.widgetWithText(FilledButton, 'Record ₹2,000 and check out'));
      await tester.pumpAndSettle();

      expect(find.text('CHECK-OUT LIST r1'), findsOneWidget);
      expect(find.textContaining('INVOICE'), findsNothing);
    });
```

(The guest group's `INVOICE r1` assertions stay as they are: the guest path is unchanged.)

In `test/core/router_test.dart`, add these imports:

```dart
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/features/admin/reception_checkout_screen.dart';
```

and add this test to the `desk checkout` group, after `builds the desk checkout from the URL alone`:

```dart
    // The success banner after a desk checkout lives in the URL's query,
    // so a reload (or the URL alone) rebuilds it.
    testWidgets('builds the check-out list with its banner from the URL alone',
        (tester) async {
      final container = ProviderContainer(overrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(_staff)),
        currentResortProvider.overrideWith(_StaffResort.new),
        checkedInProvider
            .overrideWith((ref, propertyId) async => const <Reservation>[]),
      ]);
      addTearDown(container.dispose);
      container.listen(currentUserProvider, (_, _) {});
      await container.read(currentUserProvider.future);
      final router = container.read(routerProvider);

      router.go('/admin/check-out?checkedOut=res-1');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final screen = tester.widget<ReceptionCheckoutScreen>(
          find.byType(ReceptionCheckoutScreen));
      expect(screen.checkedOutId, 'res-1');
      expect(find.text('Guest checked out'), findsOneWidget);
    });
```

- [ ] **Step 8: Run them to verify they fail**

Run: `flutter test test/features/stay/checkout_screen_test.dart test/core/router_test.dart`
Expected: FAIL. The desk tests still find `INVOICE r1` instead of `CHECK-OUT LIST r1`, and the router test gets `checkedOutId == null`.

- [ ] **Step 9: Route the query parameter and land desk checkouts on the list**

In `lib/core/router.dart`, replace

```dart
          GoRoute(
            path: '/admin/check-out',
            builder: (_, _) => const ReceptionCheckoutScreen(),
```

with

```dart
          GoRoute(
            path: '/admin/check-out',
            // `?checkedOut=<id>` after a desk checkout: the success banner
            // with the invoice download. In the URL so a reload keeps it;
            // redirectFor checks matchedLocation, which has no query.
            builder: (_, state) => ReceptionCheckoutScreen(
              checkedOutId: state.uri.queryParameters[checkedOutParam],
            ),
```

In `lib/features/stay/checkout_screen.dart`, add the import

```dart
import '../admin/reception_checkout_screen.dart' show deskCheckoutDoneLocation;
```

after `import '../booking/payment_gateway.dart';`, and replace

```dart
        ref.invalidate(roomBoardProvider);
      }
      context.go('/my-stay/invoice/${widget.reservationId}');
```

with

```dart
        ref.invalidate(roomBoardProvider);
        // Back to reception's own list, with the success banner and the
        // invoice download -- not the guest's /my-stay/invoice screen.
        context.go(deskCheckoutDoneLocation(widget.reservationId));
      } else {
        context.go('/my-stay/invoice/${widget.reservationId}');
      }
```

Also update `CheckoutScreen`'s class doc. After the sentence ending "…refuses a desk method from anyone who is not staff at the booking's resort.", add:

```dart
/// A guest's checkout ends on their invoice; a desk checkout goes back to
/// reception's check-out list ([deskCheckoutDoneLocation]).
```

- [ ] **Step 10: Run the tests to verify they pass**

Run: `flutter test test/features/stay/checkout_screen_test.dart test/core/router_test.dart test/features/admin/reception_checkout_screen_test.dart`
Expected: PASS.

- [ ] **Step 11: Whole suite and analyzer**

Run: `flutter analyze`
Expected: `2 issues found`, the two baseline infos in `service_request_screen.dart`.
Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 12: Commit**

```bash
git add lib/features/admin/desk_invoice.dart lib/features/admin/desk_checkout_banner.dart \
  lib/features/admin/reception_checkout_screen.dart lib/core/router.dart \
  lib/features/stay/checkout_screen.dart \
  test/features/admin/reception_checkout_screen_test.dart \
  test/features/stay/checkout_screen_test.dart test/core/router_test.dart
git commit -m "feat(desk): land desk checkouts on the check-out list with a success banner

A desk checkout used to end on the guest's /my-stay/invoice screen. It now
goes to /admin/check-out?checkedOut=<id>, which shows a banner with the
booking and a Download invoice action (hidden until the invoice PDF
feature is bound to deskInvoiceDownloadProvider).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Playwright phone project and phone-safe helpers

Touches only `e2e/` and `README.md`. It is verified by typecheck and by listing tests; the suite itself runs in Task 4, because the database is shared.

**Files:**
- Modify: `e2e/playwright.config.ts`
- Modify: `e2e/support/nav.ts`, `e2e/support/index.ts`
- Modify: `e2e/tests/accountant.spec.ts`, `e2e/tests/smoke.spec.ts`, `e2e/tests/owner.spec.ts`, `e2e/tests/frontdesk.spec.ts`, `e2e/tests/staff.spec.ts`, `e2e/tests/guest.spec.ts`, `e2e/tests/platform.spec.ts`
- Modify: `README.md` ("End-to-end tests (Playwright)")

**Interfaces:**
- Consumes: `currentPath`, `waitForFlutter` (`e2e/support/flutter.ts`), unchanged.
- Produces (from `e2e/support/index.ts`):
  - `WIDE_BREAKPOINT: 840`
  - `isNarrow(page: Page): boolean`
  - `useBottomNav(page: Page): Promise<void>`
  - `clickTab(page: Page, label: string): Promise<void>`
  - `reveal(page: Page, target: Locator, opts?: { over?: Locator; maxScrolls?: number }): Promise<void>`. It throws if the target never comes into view, so it doubles as a visibility assertion.
  - `revealAndClick(page: Page, target: Locator, opts?: { over?: Locator; maxScrolls?: number }): Promise<void>`
  - project names `desktop` and `phone`

- [ ] **Step 1: Install dependencies in this worktree**

`e2e/node_modules` is untracked, so a fresh worktree has none.
Run: `cd e2e && npm ci`
Expected: `added N packages`. No browser download is needed for this task.

- [ ] **Step 2: Record the starting test count**

Run: `cd e2e && npx playwright test --list | tail -1`
Expected: `Total: 44 tests in 7 files`

- [ ] **Step 3: Add the phone project**

In `e2e/playwright.config.ts`, update the doc comment's first sentence block by appending:

```ts
 * Two projects run every spec: `desktop` (1280x800, the wide layout with
 * the NavigationRail) and `phone` (a full Pixel 7: 412x839, touch, Android
 * Chrome -- the bottom navigation bar and Flutter web's mobile paths).
 * `npx playwright test --project=phone` runs one.
```

Remove `viewport: { width: 1280, height: 800 },` from the top-level `use` block, and replace

```ts
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } }],
```

with

```ts
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1280, height: 800 } } },
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
```

- [ ] **Step 4: Verify the projects are listed**

Run: `cd e2e && npx playwright test --list | tail -1`
Expected: `Total: 88 tests in 7 files`
Run: `cd e2e && npx playwright test --list --project=phone | head -3`
Expected: lines starting `[phone] ›`.

- [ ] **Step 5: Write the helpers**

Replace `clickTab` in `e2e/support/nav.ts` (the doc comment starting "Taps a bottom-navigation destination" through the end of the file) with:

```ts
/** Flutter's wide/narrow switch: PasalaTokens.wideBreakpoint (lib/core/theme/tokens.dart). */
export const WIDE_BREAKPOINT = 840;

/** Room the NavigationBar takes at the bottom of a narrow layout. */
const BOTTOM_BAR_PX = 80;

/** True when the app is laid out as a phone: bottom navigation bar, card lists. */
export function isNarrow(page: Page): boolean {
  const size = page.viewportSize();
  return !!size && size.width < WIDE_BREAKPOINT;
}

/**
 * Makes the narrow layout render: the bottom navigation bar (role=tab; the
 * wide layout's NavigationRail is not in the semantics tree at all) and the
 * card lists that replace wide DataTables. The `phone` project already is
 * narrow, so this does nothing there. On `desktop` it narrows the width to
 * 400 -- width only: widening the height too once left a full-height
 * semantics node covering the screen and intercepting every tap.
 */
export async function useBottomNav(page: Page): Promise<void> {
  const size = page.viewportSize();
  if (size && size.width >= WIDE_BREAKPOINT) {
    await page.setViewportSize({ width: 400, height: size.height });
  }
}

/** Taps a bottom-navigation destination ("Browse", "Bookings", "Owner"...). */
export async function clickTab(page: Page, label: string): Promise<void> {
  await useBottomNav(page);
  await page.getByRole('tab', { name: label, exact: true }).click();
}

type RevealOptions = {
  /** Scroll over this element (e.g. something inside a bottom sheet) instead of the screen's centre. */
  over?: Locator;
  /** Wheel steps to try downwards before searching upwards (default 15). */
  maxScrolls?: number;
};

/**
 * Scrolls until [target] is on screen, and throws if it never gets there,
 * so it is also a visibility assertion. On a phone, much of a screen sits
 * below the fold, and Flutter builds a lazy list's children only near the
 * viewport: until scrolled to, the node is not in the semantics DOM at all,
 * and Playwright's own scroll-into-view cannot find it. "On screen" means
 * visible, its top inside the viewport, and clear of the bottom navigation
 * bar on a narrow layout. The scroll direction follows the target's box
 * when it has one; an unbuilt target is searched for downwards, then
 * upwards. At desktop size most targets are already on screen, and this
 * returns at once.
 */
export async function reveal(page: Page, target: Locator, opts: RevealOptions = {}): Promise<void> {
  const { width, height } = page.viewportSize() ?? { width: 1280, height: 800 };
  const bottom = height - (isNarrow(page) ? BOTTOM_BAR_PX : 0);
  const maxScrolls = opts.maxScrolls ?? 15;
  let direction = 1; // 1 = down, -1 = up
  for (let i = 0; i < maxScrolls * 3; i++) {
    const box = (await target.isVisible()) ? await target.boundingBox() : null;
    if (box && box.y >= 0 && box.y + Math.min(box.height, 48) <= bottom) return;
    if (box) direction = box.y < 0 ? -1 : 1;
    else if (i === maxScrolls) direction = -1;
    const anchor = opts.over ? await opts.over.boundingBox({ timeout: 5_000 }).catch(() => null) : null;
    await page.mouse.move(
      anchor ? anchor.x + anchor.width / 2 : width / 2,
      anchor ? anchor.y + anchor.height / 2 : height / 2,
    );
    await page.mouse.wheel(0, direction * Math.round(height * 0.4));
    await page.waitForTimeout(250);
  }
  throw new Error(`reveal(): ${target} never came into view (${width}x${height})`);
}

/** [reveal]s [target], then clicks it. */
export async function revealAndClick(page: Page, target: Locator, opts: RevealOptions = {}): Promise<void> {
  await reveal(page, target, opts);
  await target.click();
}
```

Change the import at the top of `nav.ts` from `import { expect, type Page } from '@playwright/test';` to

```ts
import { expect, type Locator, type Page } from '@playwright/test';
```

Replace the last line of `e2e/support/index.ts`

```ts
export { clickTab, expectAt, goTo, landingPath } from './nav.ts';
```

with

```ts
export {
  WIDE_BREAKPOINT,
  clickTab,
  expectAt,
  goTo,
  isNarrow,
  landingPath,
  reveal,
  revealAndClick,
  useBottomNav,
} from './nav.ts';
```

- [ ] **Step 6: Typecheck the helpers**

Run: `cd e2e && npx tsc --noEmit`
Expected: no output (clean).

- [ ] **Step 7: Accountant: use the shared narrowing**

In `e2e/tests/accountant.spec.ts`:
- Replace the import `import { goTo, landingPath, login } from '../support/index.ts';` with `import { goTo, landingPath, login, useBottomNav } from '../support/index.ts';`.
- Delete the whole `narrow` function (from `async function narrow(page: Page): Promise<void> {` to its closing `}`).
- Replace every `await narrow(page);` (5 places) with `await useBottomNav(page);`.
- In the header comment, replace `// Every test narrows the viewport first: the accountant's bottom` with `// Every test calls useBottomNav first (a no-op on the phone project): the accountant's bottom`, and replace `// 840px breakpoint -- see nav.ts's clickTab.` with `// 840px breakpoint -- see nav.ts's useBottomNav.`.

- [ ] **Step 8: Smoke, owner and front desk: reveal content below the fold**

`e2e/tests/smoke.spec.ts`: change the support import to `import { expectAt, landingPath, login, logout, openApp, reveal } from '../support/index.ts';` and replace

```ts
  await expect(page.getByRole('button', { name: /^Business dashboard/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Team/ })).toBeVisible();
```

with

```ts
  // reveal(): on a phone the owner hub's tiles sit below the fold.
  await reveal(page, page.getByRole('button', { name: /^Business dashboard/ }));
  await reveal(page, page.getByRole('button', { name: /^Team/ }));
```

`e2e/tests/owner.spec.ts`: change the support import to `import { expectAt, fillField, goTo, landingPath, login, reveal, revealAndClick } from '../support/index.ts';` and replace

```ts
  await expect(page.getByRole('button', { name: /^Team/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Rooms/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Finance/ })).toBeVisible();
  await expect(page.getByRole('button', { name: /^Settings/ })).toBeVisible();
```

with

```ts
  // On a phone the MANAGE grid is below the fold; reveal() scrolls to each.
  for (const tile of [/^Team/, /^Rooms/, /^Finance/, /^Settings/]) {
    await reveal(page, page.getByRole('button', { name: tile }));
  }
```

Replace `  await page.getByRole('button', { name: /^Rooms/ }).click();` with `  await revealAndClick(page, page.getByRole('button', { name: /^Rooms/ }));`.
Replace `  await page.getByRole('button', { name: /^Finance/ }).click();` with `  await revealAndClick(page, page.getByRole('button', { name: /^Finance/ }));`.
In the Rooms tile test, replace

```ts
    await expect(page.getByRole('button', { name: new RegExp(`^${unit.name}`) })).toBeVisible();
```

with

```ts
    await reveal(page, page.getByRole('button', { name: new RegExp(`^${unit.name}`) }));
```

`e2e/tests/frontdesk.spec.ts`: change the support import to `import { expectAt, fillField, goTo, landingPath, login, reveal } from '../support/index.ts';` and replace

```ts
  await expect(page.getByRole('button', { name: 'New Booking', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Check-in', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Check-out', exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Rooms', exact: true })).toBeVisible();
```

with

```ts
  for (const action of ['New Booking', 'Check-in', 'Check-out', 'Rooms']) {
    await reveal(page, page.getByRole('button', { name: action, exact: true }));
  }
```

and in `units and rates screens open for Resort A`, replace

```ts
    await expect(page.getByRole('group', { name: new RegExp(`^${unit.name}`) })).toBeVisible();
```

with

```ts
    await reveal(page, page.getByRole('group', { name: new RegExp(`^${unit.name}`) }));
```

- [ ] **Step 9: Staff, guest and platform: reveal content below the fold**

`e2e/tests/staff.spec.ts`: add `reveal,` and `revealAndClick,` to the support import list. In `room grid shows tiles and summary counts`, replace the three lines

```ts
    await expect(page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}`) })).toBeVisible();
    await expect(page.getByRole('button', { name: new RegExp(`^${lakeVilla.name}`) })).toBeVisible();
    await expect(page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) })).toBeVisible();
```

with

```ts
    for (const unit of [gardenCottage, lakeVilla, treeHouse]) {
      await reveal(page, page.getByRole('button', { name: new RegExp(`^${unit.name}`) }));
    }
```

Then replace every occurrence (replace-all) of

```ts
await page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) }).click();
```

with

```ts
await revealAndClick(page, page.getByRole('button', { name: new RegExp(`^${treeHouse.name}`) }));
```

and of

```ts
await page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}`) }).click();
```

with

```ts
await revealAndClick(page, page.getByRole('button', { name: new RegExp(`^${gardenCottage.name}`) }));
```

`e2e/tests/guest.spec.ts`: change the support import to

```ts
import {
  currentPath,
  expectAt,
  fillField,
  goTo,
  landingPath,
  login,
  openApp,
  reveal,
  revealAndClick,
  waitForFlutter,
} from '../support/index.ts';
```

Then make these replacements:
- Replace-all `await expect(resortCard(page, resortA.name)).toBeVisible();` with `await reveal(page, resortCard(page, resortA.name));`.
- Replace-all `await expect(resortCard(page, guestResort.name)).toBeVisible();` with `await reveal(page, resortCard(page, guestResort.name));`.
- In `pickStayDates`, replace `  await page.getByRole('button', { name: /^Check-in/ }).click();` with `  await revealAndClick(page, page.getByRole('button', { name: /^Check-in/ }));`.
- In the resort page test, replace

```ts
  await expect(page.getByText('E2E Meadow Lane, Testville')).toBeVisible();
  // Seeded by guest-data.ts's setupGuestData: exactly one past, reviewed stay.
  const viewAllReviews = page.getByRole('button', { name: 'View All Reviews', exact: true });
  await expect(viewAllReviews).toBeVisible();
  await viewAllReviews.scrollIntoViewIfNeeded();
  await viewAllReviews.click();
```

with

```ts
  await reveal(page, page.getByText('E2E Meadow Lane, Testville'));
  // Seeded by guest-data.ts's setupGuestData: exactly one past, reviewed stay.
  const viewAllReviews = page.getByRole('button', { name: 'View All Reviews', exact: true });
  await revealAndClick(page, viewAllReviews);
```

- In `bookGuestResort`, replace

```ts
  await expect(page.getByText(/Sleeps/)).toBeVisible();

  await pickStayDates(page, startOffsetDays);

  const payButton = page.getByRole('button', { name: /^Pay ₹/ });
  await expect(payButton).toBeEnabled({ timeout: 20_000 });
```

with

```ts
  await reveal(page, page.getByText(/Sleeps/));

  await pickStayDates(page, startOffsetDays);

  const payButton = page.getByRole('button', { name: /^Pay ₹/ });
  await reveal(page, payButton);
  await expect(payButton).toBeEnabled({ timeout: 20_000 });
```

and replace

```ts
  await expect(page.getByRole('radio', { name: /Pay 35% advance now/ })).toBeVisible();
  await expect(page.getByRole('radio', { name: /Pay full amount now/ })).toBeVisible();

  await page.getByRole('button', { name: 'Pay and confirm', exact: true }).click();
```

with

```ts
  // The quote is a bottom sheet: scroll over the sheet, not the page behind it.
  const inSheet = { over: page.getByRole('radio').first() };
  await reveal(page, page.getByRole('radio', { name: /Pay 35% advance now/ }), inSheet);
  await reveal(page, page.getByRole('radio', { name: /Pay full amount now/ }), inSheet);

  await revealAndClick(page, page.getByRole('button', { name: 'Pay and confirm', exact: true }), inSheet);
```

- In the cancel test, replace `    await page.getByRole('button', { name: 'Cancel booking', exact: true }).click();` with `    await revealAndClick(page, page.getByRole('button', { name: 'Cancel booking', exact: true }));`.
- In the My Stay test, replace `  await expect(page.getByRole('button', { name: 'Checkout', exact: true })).toBeVisible();` with `  await reveal(page, page.getByRole('button', { name: 'Checkout', exact: true }));`.
- In the unit-picker test, replace

```ts
    await expect(page.getByText('Choose your stay', { exact: true })).toBeVisible();
    await expect(page.getByText(/Sleeps/)).toBeVisible({ timeout: 5_000 });
```

with

```ts
    await reveal(page, page.getByText('Choose your stay', { exact: true }));
    await reveal(page, page.getByText(/Sleeps/));
```

`e2e/tests/platform.spec.ts`: change the support import to `import { fillField, landingPath, login, reveal, revealAndClick, waitForFlutter } from '../support/index.ts';`. In `chooseFromMenu`, replace `  await trigger.click();` with

```ts
  // After revealing a card further down, the trigger may be above the fold.
  await revealAndClick(page, trigger);
```

Then replace-all `await expect(cardA).toBeVisible();` with `await reveal(page, cardA);`, `await expect(cardB).toBeVisible();` with `await reveal(page, cardB);`, and `await expect(cardS).toBeVisible();` with `await reveal(page, cardS);`.

- [ ] **Step 10: Typecheck and list**

Run: `cd e2e && npx tsc --noEmit`
Expected: clean.
Run: `cd e2e && npx playwright test --list | tail -1`
Expected: `Total: 88 tests in 7 files`

- [ ] **Step 11: Document the projects**

In `README.md`, "End-to-end tests (Playwright)", replace the first paragraph's first sentence

```markdown
`e2e/` holds a Playwright suite (Chromium) that drives the real web build
against the local Supabase stack.
```

with

```markdown
`e2e/` holds a Playwright suite (Chromium) that drives the real web build
against the local Supabase stack. Every spec runs twice: in the `desktop`
project (1280x800, navigation rail) and in the `phone` project (a Pixel 7:
412x839, touch, Android Chrome, bottom navigation bar). Specs call
`reveal()` (`e2e/support/nav.ts`) before touching anything that can sit
below a phone's fold, because Flutter builds lazy lists only near the
viewport.
```

and in the command block replace

```bash
npx playwright test                  # serves build/web on :8790 and runs every spec
```

with

```bash
npx playwright test                  # serves build/web on :8790 and runs every spec, desktop then phone
npx playwright test --project=desktop            # 1280x800 only
npx playwright test --project=phone              # Pixel 7 only
```

- [ ] **Step 12: Optional run (only if the orchestrator says the shared stack is free)**

Run: `supabase status` (from the repo root). If the stack is up and no other E2E run or `db` work is in progress, run `cd e2e && ./build-app.sh && npx playwright test --project=phone`, and fix any phone-only failure with the triage table in Task 4, Step 7. Otherwise skip: Task 4 runs both projects.

- [ ] **Step 13: Commit**

```bash
git add e2e/playwright.config.ts e2e/support/nav.ts e2e/support/index.ts e2e/tests README.md
git commit -m "test(e2e): add a Pixel 7 phone project and phone-safe helpers

Every spec now runs at desktop (1280x800) and phone (Pixel 7) size.
useBottomNav replaces the accountant spec's own narrowing; reveal and
revealAndClick scroll lazy Flutter lists until a target is on screen.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Integration — bind the P2 invoice download, E2E at both sizes, report

Runs after Tasks 1-3 and **after P2 (PDF invoices) is merged** into the branch. It needs the local Supabase stack (no migrations) for Playwright.

**Files:**
- Modify: `lib/features/admin/desk_invoice.dart`
- Create: `test/features/admin/desk_invoice_test.dart`
- Modify: `e2e/tests/frontdesk.spec.ts`
- Modify: `e2e/REPORT.md`
- Possibly modify (phone triage only): `e2e/support/nav.ts`, `e2e/support/flutter.ts`, `e2e/tests/*.spec.ts`

**Interfaces:**
- Consumes: `deskInvoiceDownloadProvider` / `DeskInvoiceDownload` (Task 2); `reveal`, `revealAndClick` (Task 3); P2's booking-invoice PDF entry point (the function P2's guest invoice / booking detail "Download invoice" button calls).
- Produces: a non-null `deskInvoiceDownloadProvider`, and a green E2E run under `desktop` and `phone`.

- [ ] **Step 1: Find P2's invoice entry point**

Run:
```bash
ls docs/superpowers/plans/ | grep -i -E "p2|pdf|invoice"
grep -n -A6 "Produces" docs/superpowers/plans/*p2*pdf*.md | grep -i -E "invoice|pdf"
grep -rn -i -E "invoice.*(pdf|download|share)|(pdf|download|share).*invoice" lib | grep -v "^lib/features/admin/desk_"
grep -n -E "^\s+(pdf|printing):" pubspec.yaml
```
Expected: `pdf` and `printing` are in `pubspec.yaml`, and there is one function or provider that builds a reservation's invoice PDF and hands it to the platform. On the web that is a download (e.g. `Printing.sharePdf(bytes: …, filename: '….pdf')`). Note its exact name, its parameters, and whether it takes a `Ref`, a `WidgetRef`, a `BuildContext` or plain data. If P2 only offers a print dialog on the web (`Printing.layoutPdf`), stop and report it to the orchestrator. The spec requires a file download.

- [ ] **Step 2: Write the failing binding test**

Create `test/features/admin/desk_invoice_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/admin/desk_invoice.dart';

void main() {
  // The check-out banner hides Download invoice while this is null; once
  // the invoice PDF feature (P2) is merged it must be bound.
  test('the desk invoice download is bound to the invoice PDF feature', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(deskInvoiceDownloadProvider), isNotNull);
  });
}
```

Run: `flutter test test/features/admin/desk_invoice_test.dart`
Expected: FAIL: `Expected: not null  Actual: <null>`.

- [ ] **Step 3: Bind it**

In `lib/features/admin/desk_invoice.dart`, add the import of P2's file found in Step 1. Then replace

```dart
/// `null` until the invoice PDF feature (P2) is bound here. The check-out
/// banner hides its Download invoice button while it is. A provider, like
/// `csvDownloaderProvider`, so widget tests can capture the call.
final deskInvoiceDownloadProvider =
    Provider<DeskInvoiceDownload?>((ref) => null);
```

with the binding below. Call P2's entry point exactly as its own guest-side button does, passing whichever of `ref` (provider `Ref`), `widgetRef`, `context` and `reservationId` it takes:

```dart
/// Bound to the invoice PDF feature (P2): builds this booking's invoice PDF
/// and saves it (a `.pdf` download on the web). A provider, like
/// `csvDownloaderProvider`, so widget tests can capture the call.
final deskInvoiceDownloadProvider = Provider<DeskInvoiceDownload?>(
  (ref) => (context, widgetRef, reservationId) =>
      // P2's entry point from Step 1, e.g. `downloadBookingInvoice(ref, reservationId)`
      // or `widgetRef.read(invoicePdfServiceProvider).download(reservationId)`.
      p2InvoiceEntryPoint(context, widgetRef, reservationId),
);
```

`p2InvoiceEntryPoint` stands for the call you found in Step 1. Write the real call in its place, and remove the example comment once it compiles. If the entry point returns something other than `Future<void>` (for example a `Future<bool>` "delivered" flag like `CsvDownloader`), throw `const InvalidState('Could not save the invoice.')` (import `../../core/errors.dart`) when it reports failure, so the banner shows a message.

- [ ] **Step 4: Run the binding test and the Flutter suite**

Run: `flutter test test/features/admin/desk_invoice_test.dart`
Expected: PASS.
Run: `flutter analyze`
Expected: `2 issues found` (the baseline infos).
Run: `flutter test`
Expected: all pass. The banner tests override the provider, so they are unaffected.

- [ ] **Step 5: E2E: the desk checkout lands on the list and downloads the invoice**

In `e2e/tests/frontdesk.spec.ts`, rename the test `'reception checks the guest out with a desk Cash payment and reference; the room needs cleaning afterwards'` to `'reception checks the guest out with a desk Cash payment and reference, lands back on the list with the invoice, and the room needs cleaning'`, and replace

```ts
  await page.getByRole('button', { name: /^Record .* and check out$/ }).click();

  // checkout_booking succeeds and lands on the final invoice.
  await expectAt(page, `/my-stay/invoice/${frontdeskBookingId}`);
  await expect(page.getByRole('heading', { name: 'Final Invoice' })).toBeVisible();
```

with

```ts
  await page.getByRole('button', { name: /^Record .* and check out$/ }).click();

  // checkout_booking succeeds and reception is back on its own check-out
  // list -- not the guest's /my-stay/invoice -- with a success banner (in
  // the URL, so a reload keeps it) and the booking's invoice PDF.
  await expectAt(page, '/admin/check-out');
  await expect
    .poll(() => page.evaluate(() => window.location.hash))
    .toBe(`#/admin/check-out?checkedOut=${frontdeskBookingId}`);
  await expect(page.getByRole('heading', { name: 'Check-Out' })).toBeVisible();
  // Scoped to the semantics host: the banner is a live region, so Flutter
  // also copies its text into the hidden aria-live announcer.
  await expect(page.locator('flt-semantics-host').getByText(/Guest checked out/).first()).toBeVisible();
  await expect(outRow).toBeHidden();

  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.getByRole('button', { name: 'Download invoice', exact: true }).click(),
  ]);
  expect(download.suggestedFilename()).toMatch(/\.pdf$/);
```

Also update the file header's comment "(confirmed -> checked in -> checked out)" paragraph if it mentions the invoice. It does not today, so leave it.

Run: `cd e2e && npx tsc --noEmit`
Expected: clean.

- [ ] **Step 6: Build and run both projects**

Check the shared stack first. Run `supabase status` from the repo root; expected: the API URL `http://127.0.0.1:54321` is running. Do not run while another worktree's E2E run is in progress, and never `supabase db reset`.

Run:
```bash
cd e2e && npm ci && npx playwright install chromium && ./build-app.sh
npx playwright test --project=desktop
```
Expected: `44 passed`.

Run: `npx playwright test --project=phone`
Expected: `44 passed`. Fix any failure with Step 7, then re-run that spec with `npx playwright test --project=phone tests/<file>.spec.ts` until it passes.

- [ ] **Step 7: Phone-only failure triage (apply only what a failure calls for)**

Open the failure's trace (`npx playwright show-trace test-results/<dir>/trace.zip`) and match the symptom:

| Symptom | Fix (in the helper or the spec, never by removing `isMobile`/`hasTouch`) |
|---|---|
| `toBeVisible` / click times out on an element that exists further down the screen | Replace that `expect(x).toBeVisible()` or `x.click()` with `await reveal(page, x)` or `await revealAndClick(page, x)`. |
| `reveal(): … never came into view` although the target exists below, and the page did not move | The wheel does not scroll under phone emulation. In `reveal`, replace the two `page.mouse` lines with a CDP touch scroll: `const cdp = await page.context().newCDPSession(page); await cdp.send('Input.synthesizeScrollGesture', { x: Math.round(cx), y: Math.round(cy), yDistance: -direction * Math.round(height * 0.4), gestureSourceType: 'touch', speed: 1500 }); await cdp.detach();` (with `cx`/`cy` the same point the mouse moved to), and keep the wheel for `!isNarrow(page)`. |
| A click lands on the bottom bar or a different element | The target was under the NavigationBar. Use `revealAndClick`: its in-view check keeps the target above the bar. |
| `fillField` keeps retrying and the value never survives the blur | Flutter web's mobile text input strategy. In `e2e/support/flutter.ts` `fillField`, after `field.click()` add `await field.page().keyboard.press('End');` and use `await field.pressSequentially(value, { delay: 20 })` instead of `field.fill(value)` when `field.page().viewportSize()!.width < 840`. |
| Strict mode: 2 elements for a locator that is unique at desktop | The phone layout renders a second copy (e.g. a tab and a button with one name). Scope it: `page.locator('flt-semantics-host').getByRole(…)`, or the containing `group`. |
| The spec narrows with `setViewportSize` itself | Replace it with `useBottomNav(page)`. |

- [ ] **Step 8: Full run, twice**

Run: `cd e2e && npx playwright test` (both projects, one after the other), twice.
Expected: both runs `88 passed`, 0 failed, 0 flaky. Then check the teardown:

```bash
docker exec supabase_db_pasala_farm psql -U postgres -tAc \
  "select (select count(*) from auth.users where email like '%@e2e.resorthub.test'), (select count(*) from public.properties where slug like 'e2e-%')"
```

Expected: `0|0`.
Run: `grep -rn "test.fail\|test.fixme\|test.skip" e2e/tests`
Expected: no output.

- [ ] **Step 9: Update the report**

In `e2e/REPORT.md`:
- In the header paragraph, replace "It runs one worker, in Chromium, at 1280x800." with "It runs one worker, in Chromium, in two projects: `desktop` (1280x800) and `phone` (Pixel 7: 412x839, touch, Android Chrome).".
- In "Run results", add these rows, with the counts and times from Step 6 and Step 8:
  - `| Playwright, desktop project | **44 passed**, 0 failed (<time>) |`
  - `| Playwright, phone project | **44 passed**, 0 failed (<time>) |`
  - `| Playwright, both projects, final runs 1 and 2 | **88 passed** each, 0 flaky |`
- In the Front desk row of "Coverage per persona", replace "check-out with a desk Cash payment and reference, after which the room needs cleaning" with "check-out with a desk Cash payment and reference, back on the check-out list with a success banner and a PDF invoice download, after which the room needs cleaning".
- In "Remaining gaps and follow-ups", delete the bullet "**Only the wide layout (1280x800) is covered** …" and the sub-bullet "The desk checkout ends on a guest invoice route (ops Minor 6)." Add under "Visual checks": "Both sizes are covered by behaviour (bottom navigation, `reveal()` for below-the-fold content), not by screenshots."
- Add a short section "## Phone project (P5)" listing each fix Step 7 needed (symptom → fix, one line each), or "No phone-only fixes were needed beyond `reveal()`." if none.

- [ ] **Step 10: Commit**

```bash
git add lib/features/admin/desk_invoice.dart test/features/admin/desk_invoice_test.dart \
  e2e/tests e2e/support e2e/REPORT.md
git commit -m "feat(desk): download the invoice PDF after a desk checkout; E2E at phone size

Binds deskInvoiceDownloadProvider to the invoice PDF feature, checks the
new desk checkout landing in frontdesk.spec.ts, and reports the suite at
desktop and Pixel 7 size.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:**
  - Decision 1 (land on the list, success message, Download invoice): Task 2, bound in Task 4.
  - Decision 2 / 8 (P0021): Task 1, plus Task 2's P0021 banner test.
  - Decision 3 / 9 / 10 / 11 (phone project, helpers, both projects in one run): Task 3, run in Task 4.
  - Decision 4 (URL): Tasks 2 and 4.
  - Decision 5 (banner, live region, above the empty state): Task 2.
  - Decision 6 (short id): Task 2.
  - Decision 7 (seam, `null` until P2): Tasks 2 and 4.
  - Decision 12 (no DB): nothing to build.
  - README and REPORT: Tasks 3 and 4.
- **Placeholders:** `p2InvoiceEntryPoint` in Task 4 Step 3 is deliberately named as the one lookup. P2's plan is being written in parallel, and Step 1 gives the exact commands to find it. Run results in the REPORT come from the run itself.
- **Type consistency:**
  - `DeskInvoiceDownload(BuildContext, WidgetRef, String)` is used the same way in `desk_invoice.dart`, the banner (`download(context, ref, widget.reservationId)`), the tests (`(_, _, reservationId)`) and the binding.
  - `checkedOutParam`, `deskCheckoutDoneLocation` and `checkedOutId` match across the router, the screen, the tests and `CheckoutScreen`.
  - `reveal` / `revealAndClick` / `useBottomNav` match between `nav.ts`, `index.ts` and the specs.
- **Review Focus:**
  - 1-3 have tests in Task 2.
  - 4-5 are built into `reveal` (Task 3) and exercised by the phone run in Task 4.

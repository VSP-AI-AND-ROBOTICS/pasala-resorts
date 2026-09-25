# PDF Invoices and Report PDFs (P2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Guests, reception, owners/admins and accountants can download a booking invoice as a PDF, and the Finance Collections, Ledger and Settlements reports can be exported as PDF next to CSV.

**Architecture:** Everything is client-side Flutter. `package:pdf` lays documents out from two plain models (`Invoice`, `ReportPdf`); `InvoiceRepository` builds an `Invoice` from reads the viewer is already allowed by RLS plus `current_charges`, and a pure `buildInvoice` enforces the rules. Three Riverpod seams (`invoiceSourceProvider`, `pdfExporterProvider`, `pdfDelivererProvider`) keep every screen testable with fakes; delivery is a Blob download on the web and `Printing.sharePdf` elsewhere. No database change.

**Tech Stack:** Flutter 3 / Dart 3.10, Riverpod 3, go_router, supabase_flutter 2, `pdf`, `printing`, `package:web`, flutter_test, Playwright (integration only).

**Spec:** `docs/superpowers/specs/2026-09-25-p2-pdf-invoices-and-report-pdfs-design.md`

## Global Constraints

- New runtime dependencies: only `pdf` and `printing` (added with `flutter pub add pdf printing`). Fonts: Noto Sans Regular and Bold (SIL OFL 1.1) in `assets/fonts/` with `OFL.txt`.
- No migration, SQL, pgTAP, Edge Function, RLS, route or router role-matrix change.
- Money in PDFs prints like `formatMoney`: `₹1,080.00` (`en_IN`, 2 decimals). Dates print `d MMM yyyy` in device local time.
- Invoice number: `<slug upper-cased>-<first 8 hex digits of the reservation id upper-cased>` (e.g. `PASALA-3F2A9C1B`); invoice file `invoice-<NUMBER>.pdf`; report files `<slug>-<report>-<yyyy-MM-dd>-<yyyy-MM-dd>.pdf`.
- Totals, paid and amount due come from `current_charges`; if the category lines differ from `current_charges.total` by more than ₹0.01 the invoice is refused.
- Copy, verbatim: "Download invoice (PDF)", "Preparing invoice…", tooltip "Invoice PDF", tooltip "Export PDF", "Invoice <NUMBER> is ready.", "Invoice download isn't available on this device yet.", "Couldn't create the invoice PDF. Try again.", "PDF exported.", "PDF export isn't available on this platform yet.", "Couldn't create the PDF. Try again.", "An invoice is available once the guest has checked in.", "Only guest bookings have an invoice.", "This resort isn't taking bookings right now, so its invoice can't be issued. Contact the resort.", "The bill changed while the invoice was being prepared. Try again.", "The stay is still in progress, so this bill may change before checkout.", "Tax is charged on the room and cleaning fee after the coupon discount."
- Do not edit `lib/features/stay/checkout_screen.dart`, `lib/core/errors.dart`, `lib/features/finance/finance_tables.dart` or `lib/features/finance/finance_csv.dart` (P4/P5 work there); only read from them.
- TDD with `flutter test`. `flutter analyze` must show only the baseline: 2 infos in `service_request_screen.dart`.
- Never run `dart format` on whole directories or pre-existing files; format only files you create (`dart format <path>`).
- Keep the `pubspec.lock` changes that come from adding `pdf`/`printing`; revert any unrelated SDK-only lock bumps.
- Every commit message ends with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. **The bill changes while the invoice is being read** (a food order or payment lands between the five reads) — expect a refusal "The bill changed while the invoice was being prepared. Try again.", never a PDF whose lines don't add up to its total. Pinned in Task 2 ("refuses a bill that changed between reads").
2. **A guest of a resort that has since been suspended/archived** (RLS hides the `properties` embed) — expect the clear refusal, not an invoice without number or GSTIN. Pinned in Task 3 ("a resort hidden by RLS parses as no resort") and Task 2 ("refuses when the resort cannot be read").
3. **Names or addresses with characters the font lacks** (Devanagari, emoji) — expect the PDF to render with `?` in their place. Pinned in Task 1 (`safe()`) and Task 4 (renderer tests with `सीता 🌸`).
4. **A long report range** (hundreds of days, thousands of settlements) — expect a multi-page PDF past `pdf`'s default 20-page cap, header row repeated. Pinned in Task 4 ("long reports run to many pages").
5. **Double taps** on "Download invoice (PDF)" / "Export PDF" — expect one export at a time. Pinned in Task 5 ("a second tap while working does nothing") and Task 7 ("a second tap while a PDF is being made does nothing").

---

## Execution order and parallelism

There is no database work, so every task is a TRACK task (Flutter only, runnable with fakes). Task 1 fixes all shared contracts (models, seams, providers, fakes). After it:

- Task 2 → Task 3 (invoice data), sequential.
- Task 4 (renderers + real exporter) — independent.
- Task 5 (invoice UI) — independent; tests use the fakes from Task 1.
- Task 6 → Task 7 (report PDFs), sequential.
- Task 8 integrates after all.

Tasks 2–7 touch disjoint files, so the three chains {2,3}, {4}, {5}, {6,7} can run in parallel after Task 1.

## File structure

| File | Task | Responsibility |
|---|---|---|
| `pubspec.yaml`, `pubspec.lock` | 1 | `pdf`, `printing`; font assets |
| `assets/fonts/NotoSans-Regular.ttf`, `NotoSans-Bold.ttf`, `OFL.txt` | 1 | bundled font + licence |
| `lib/core/pdf/pdf_fonts.dart` | 1 | `PdfFonts`, `loadPdfFonts`, asset paths |
| `lib/core/pdf/pdf_format.dart` | 1 | `pdfMoney`, `pdfDate` |
| `lib/core/pdf/pdf_delivery.dart` | 1 | `PdfDeliverer`, `pdfDelivererProvider` |
| `lib/core/pdf/pdf_deliver.dart` | 1 | conditional export of `deliverPdf` |
| `lib/core/pdf/pdf_deliver_share.dart` | 1 | non-web `deliverPdf` via `Printing.sharePdf` |
| `lib/core/pdf/pdf_deliver_web.dart` | 1 | web `deliverPdf` via Blob download |
| `lib/core/pdf/report_pdf.dart` | 1 | `ReportPdf`, `ReportPdfColumn` models |
| `lib/core/pdf/pdf_exporter.dart` | 1 (stub), 4 | `PdfExporter`, `PasalaPdfExporter`, `pdfExporterProvider` |
| `lib/data/models/invoice.dart` | 1 | invoice models |
| `lib/data/repositories/invoice_repository.dart` | 1 (stub), 3 | `InvoiceSource`, `InvoiceRepository`, providers |
| `test/support/pdf_test_fonts.dart` | 1 | fonts from disk for tests |
| `test/support/fake_pdf_exporter.dart` | 1 | `FakePdfExporter`, `PdfDeliveries` |
| `test/support/fake_invoice_source.dart` | 1 | `FakeInvoiceSource`, `sampleInvoice` |
| `lib/data/models/invoice_builder.dart` | 2 | `invoiceNumber`, `buildInvoice` |
| `lib/core/pdf/report_pdf_renderer.dart` | 4 | `buildReportDocument`, `renderReportPdf` |
| `lib/core/pdf/invoice_pdf_renderer.dart` | 4 | `buildInvoiceDocument`, `renderInvoicePdf` |
| `lib/features/invoice/invoice_pdf_button.dart` | 5 | `downloadInvoicePdf`, `InvoicePdfButton` |
| `lib/features/account/booking_detail_screen.dart` | 5 | invoice card for checked-in/out bookings |
| `lib/features/stay/final_invoice_screen.dart` | 5 | invoice button |
| `lib/features/finance/finance_settlements_tab.dart` | 5 | per-row invoice button |
| `lib/features/finance/finance_pdf.dart` | 6 | `financePdfFileName`, `collectionsPdf`, `ledgerPdf`, `settlementsPdf` |
| `lib/features/finance/finance_screen.dart` | 7 | Export PDF action |
| `lib/features/owner/owner_reports_screen.dart` | 7 | PDF buttons on the finance tiles |
| `e2e/support/accountant-data.ts`, `e2e/tests/accountant.spec.ts`, `README.md` | 8 | integration |

---

### Task 1: PDF foundation and shared contracts

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `assets/fonts/NotoSans-Regular.ttf`, `assets/fonts/NotoSans-Bold.ttf`, `assets/fonts/OFL.txt`
- Create: `lib/core/pdf/pdf_fonts.dart`, `lib/core/pdf/pdf_format.dart`, `lib/core/pdf/pdf_delivery.dart`, `lib/core/pdf/pdf_deliver.dart`, `lib/core/pdf/pdf_deliver_share.dart`, `lib/core/pdf/pdf_deliver_web.dart`, `lib/core/pdf/report_pdf.dart`, `lib/core/pdf/pdf_exporter.dart`
- Create: `lib/data/models/invoice.dart`, `lib/data/repositories/invoice_repository.dart`
- Create: `test/support/pdf_test_fonts.dart`, `test/support/fake_pdf_exporter.dart`, `test/support/fake_invoice_source.dart`
- Test: `test/core/pdf/pdf_fonts_test.dart`, `test/core/pdf/pdf_format_test.dart`, `test/data/invoice_test.dart`

**Interfaces:**
- Consumes: `formatDate` (`lib/core/format.dart`), `PaymentMethod` (`lib/data/models/payment_method.dart`), `Reservation` (`lib/data/models/reservation.dart`), `CurrentCharges` (`lib/data/models/current_charges.dart`), `supabaseProvider` (`lib/core/supabase_client.dart`).
- Produces:
  - `const String pdfFontRegularAsset = 'assets/fonts/NotoSans-Regular.ttf'`, `const String pdfFontBoldAsset = 'assets/fonts/NotoSans-Bold.ttf'`
  - `class PdfFonts { factory PdfFonts.fromBytes(ByteData regular, ByteData bold); pw.Font regular; pw.Font bold; pw.ThemeData get theme; bool supports(int rune); String safe(String text); }`
  - `Future<PdfFonts> loadPdfFonts([AssetBundle? bundle])`
  - `String pdfMoney(num amount)`, `String pdfDate(DateTime d)`
  - `typedef PdfDeliverer = Future<bool> Function(String filename, Uint8List bytes)`; `final pdfDelivererProvider = Provider<PdfDeliverer>`; `Future<bool> deliverPdf(String filename, Uint8List bytes)`
  - `class ReportPdfColumn { const ReportPdfColumn(String header, {bool numeric = false, double flex = 1}); }`
  - `class ReportPdf { const ReportPdf({required String title, required String resortName, required String gstinLabel, required String periodLabel, required String fileName, required List<ReportPdfColumn> columns, required List<List<String>> rows, List<String>? totals, List<String> notes = const [], String emptyMessage = 'Nothing to report in this period.'}); }`
  - `abstract class PdfExporter { Future<Uint8List> invoice(Invoice invoice); Future<Uint8List> report(ReportPdf report); }`; `class PasalaPdfExporter implements PdfExporter` (stub here, real in Task 4); `final pdfExporterProvider = Provider<PdfExporter>`
  - Invoice models (exact fields below): `InvoiceResort`, `InvoiceCharge`, `InvoicePaymentKind`, `InvoicePayment`, `InvoiceInput`, `InvoiceLineKind`, `InvoiceLine`, `Invoice`
  - `abstract class InvoiceSource { Future<Invoice> invoice(String reservationId); }`; `class InvoiceRepository implements InvoiceSource { InvoiceRepository(SupabaseClient db); }` (stub here, real in Task 3); `invoiceRepositoryProvider`, `invoiceSourceProvider`
  - Test support: `PdfFonts testPdfFonts()`; `FakePdfExporter` (`invoices`, `reports`, `error`, `hold`, `static final Uint8List bytes`); `PdfDeliveries({bool delivers = true})` with `files` and `Future<bool> deliver(String, Uint8List)`; `FakeInvoiceSource` (`value`, `error`, `hold`, `calls`); `Invoice sampleInvoice({...})`

- [ ] **Step 1: Add the packages**

Run (in the worktree root):
```bash
flutter pub add pdf printing
git diff --stat pubspec.yaml pubspec.lock
```
Expected: `pubspec.yaml` gains `pdf: ^3.…` and `printing: ^5.…` under `dependencies`; `pubspec.lock` gains `pdf`, `printing` and their transitive packages (`archive`, `barcode`, `bidi`, `image`, `pdf_widget_wrapper`, … — whatever the resolver picks). If the lock also bumps unrelated SDK-pinned packages only because of the local SDK, revert those hunks.

Then put a comment above the two new lines in `pubspec.yaml`, matching the file's style:
```yaml
  # Booking invoices and Finance report PDFs, laid out client-side
  # (lib/core/pdf/). `printing` delivers them through the platform share
  # sheet on Android/iOS/desktop; the web downloads them directly
  # (lib/core/pdf/pdf_deliver_web.dart).
  pdf: ^3.11.3
  printing: ^5.14.2
```
(keep whatever version constraints `flutter pub add` wrote).

- [ ] **Step 2: Add the fonts and their licence**

```bash
mkdir -p assets/fonts
curl -fL -o assets/fonts/NotoSans-Regular.ttf https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf
curl -fL -o assets/fonts/NotoSans-Bold.ttf https://github.com/notofonts/notofonts.github.io/raw/main/fonts/NotoSans/hinted/ttf/NotoSans-Bold.ttf
curl -fL -o assets/fonts/OFL.txt https://raw.githubusercontent.com/notofonts/latin-greek-cyrillic/main/OFL.txt
file assets/fonts/*.ttf
```
Expected: both `.ttf` files report `TrueType Font data` and are larger than 300 KB; `OFL.txt` starts with "Copyright" and contains "SIL OPEN FONT LICENSE Version 1.1". If a URL 404s, use the jsDelivr mirror `https://cdn.jsdelivr.net/gh/notofonts/notofonts.github.io/fonts/NotoSans/hinted/ttf/NotoSans-Regular.ttf` (and `-Bold.ttf`).

In `pubspec.yaml`, under `flutter: assets:`, list the two font files explicitly (not the directory, so `OFL.txt` is not bundled):
```yaml
  assets:
    - assets/images/
    # PDF fonts (Noto Sans, SIL OFL 1.1 -- assets/fonts/OFL.txt): the
    # built-in PDF fonts have no ₹ sign.
    - assets/fonts/NotoSans-Regular.ttf
    - assets/fonts/NotoSans-Bold.ttf
```

Run: `flutter pub get` — Expected: exit 0.

- [ ] **Step 3: Write the failing tests**

`test/support/pdf_test_fonts.dart`:
```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:pasala/core/pdf/pdf_fonts.dart';

/// The bundled PDF fonts read straight from disk (`flutter test` runs in
/// the package root), for renderer tests that do not go through the app's
/// asset bundle.
PdfFonts testPdfFonts() =>
    PdfFonts.fromBytes(_read(pdfFontRegularAsset), _read(pdfFontBoldAsset));

ByteData _read(String path) =>
    ByteData.sublistView(File(path).readAsBytesSync());
```

`test/core/pdf/pdf_fonts_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_fonts.dart';

import '../../support/pdf_test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled font has the rupee sign and Latin text', () {
    final fonts = testPdfFonts();
    expect(fonts.supports(0x20B9), isTrue, reason: '₹');
    expect(fonts.supports('A'.codeUnitAt(0)), isTrue);
    expect(fonts.supports('–'.codeUnitAt(0)), isTrue, reason: 'en dash');
    expect(fonts.supports('·'.codeUnitAt(0)), isTrue, reason: 'middle dot');
  });

  test('safe() keeps what the font draws and replaces the rest with ?', () {
    final fonts = testPdfFonts();
    expect(fonts.safe('Gita Guest ₹1,080.00'), 'Gita Guest ₹1,080.00');
    expect(fonts.safe('Line 1\nLine 2\tend'), 'Line 1\nLine 2\tend');
    expect(fonts.safe('सीता'), '????');
    expect(fonts.safe('Spa 🌸'), 'Spa ?');
  });

  test('loadPdfFonts reads both fonts from the app bundle', () async {
    final fonts = await loadPdfFonts();
    expect(fonts.supports(0x20B9), isTrue);
  });
}
```

`test/core/pdf/pdf_format_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_format.dart';

void main() {
  test('pdfMoney keeps paise, the rupee sign and Indian grouping', () {
    expect(pdfMoney(1080), '₹1,080.00');
    expect(pdfMoney(123456.5), '₹1,23,456.50');
    expect(pdfMoney(0), '₹0.00');
    final negative = pdfMoney(-1000);
    expect(negative.startsWith('-'), isTrue);
    expect(negative, contains('1,000.00'));
  });

  test('pdfDate prints d MMM yyyy', () {
    expect(pdfDate(DateTime(2026, 8, 12, 11)), '12 Aug 2026');
  });
}
```

`test/data/invoice_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_invoice_source.dart';

void main() {
  test('totals add up the lines', () {
    final invoice = sampleInvoice();
    expect(invoice.subtotal, 11300);
    expect(invoice.taxTotal, 1360);
    expect(invoice.total, 12660);
    expect(invoice.advancePaid, 3192);
  });

  test('title and file name', () {
    expect(sampleInvoice().title, 'Invoice');
    expect(sampleInvoice(provisional: true).title, 'Provisional bill');
    expect(sampleInvoice().fileName, 'invoice-FIN-R-3F2A9C1B.pdf');
  });

  test('a line total is its amount plus its tax', () {
    final room = sampleInvoice().lines.first;
    expect(room.total, 11080);
  });
}
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `flutter test test/core/pdf test/data/invoice_test.dart`
Expected: FAIL — compilation errors, `pdf_fonts.dart`, `pdf_format.dart`, `fake_invoice_source.dart` not found.

- [ ] **Step 5: Implement the PDF core files**

`lib/core/pdf/pdf_fonts.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

/// Noto Sans (SIL OFL 1.1, assets/fonts/OFL.txt). The PDF standard fonts
/// have no ₹ sign, so every document this app makes uses these instead.
const pdfFontRegularAsset = 'assets/fonts/NotoSans-Regular.ttf';
const pdfFontBoldAsset = 'assets/fonts/NotoSans-Bold.ttf';

/// Whitespace the layout needs even though a font has no glyph for it.
const _alwaysKept = {0x09, 0x0A, 0x0D, 0x20};

/// The two fonts every PDF is set in, and the characters they can draw.
class PdfFonts {
  PdfFonts._(this.regular, this.bold, this._supported);

  factory PdfFonts.fromBytes(ByteData regular, ByteData bold) => PdfFonts._(
        pw.Font.ttf(regular),
        pw.Font.ttf(bold),
        TtfParser(regular).charToGlyphIndexMap.keys.toSet(),
      );

  final pw.Font regular;
  final pw.Font bold;
  final Set<int> _supported;

  /// Base and bold fonts for `pw.Document(theme: ...)`.
  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold);

  bool supports(int rune) => _supported.contains(rune);

  /// [text] with every character the font cannot draw (Devanagari, emoji,
  /// ...) replaced by `?`, so a guest's name never breaks a document.
  String safe(String text) => String.fromCharCodes(text.runes.map(
        (r) => _alwaysKept.contains(r) || _supported.contains(r) ? r : 0x3F,
      ));
}

/// Loads both fonts from the app's asset bundle.
Future<PdfFonts> loadPdfFonts([AssetBundle? bundle]) async {
  final assets = bundle ?? rootBundle;
  final regular = await assets.load(pdfFontRegularAsset);
  final bold = await assets.load(pdfFontBoldAsset);
  return PdfFonts.fromBytes(regular, bold);
}
```
If `TtfParser` is not exported from `package:pdf/pdf.dart` in the resolved version, find it with the dart MCP `rip_grep_packages` (`class TtfParser`) and import the library that exports it.

`lib/core/pdf/pdf_format.dart`:
```dart
import 'package:intl/intl.dart';

import '../format.dart';

final _money =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// `1080` -> `₹1,080.00`: paise kept, like the Finance screen's
/// `formatMoney`, because a document is a record, not a glance.
String pdfMoney(num amount) => _money.format(amount);

/// `12 Aug 2026`, in the device's local time like every date in the app.
String pdfDate(DateTime d) => formatDate(d.toLocal());
```

`lib/core/pdf/pdf_delivery.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_deliver.dart';

/// Hands a finished PDF to the user: a download on the web, the share sheet
/// elsewhere. Returns false where the platform cannot take it. A provider so
/// widget tests can capture the file instead.
typedef PdfDeliverer = Future<bool> Function(String filename, Uint8List bytes);

final pdfDelivererProvider = Provider<PdfDeliverer>((ref) => deliverPdf);
```

`lib/core/pdf/pdf_deliver.dart`:
```dart
// Web: a Blob download, exactly like csv_download_web.dart, so the browser
// (and Playwright) sees an ordinary download. Everywhere else: the
// platform share sheet through package:printing.
export 'pdf_deliver_share.dart'
    if (dart.library.js_interop) 'pdf_deliver_web.dart';
```

`lib/core/pdf/pdf_deliver_share.dart`:
```dart
import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Android, iOS and desktop: the platform share sheet (save, print, send).
Future<bool> deliverPdf(String filename, Uint8List bytes) =>
    Printing.sharePdf(bytes: bytes, filename: filename);
```

`lib/core/pdf/pdf_deliver_web.dart`:
```dart
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: an in-memory Blob and a throwaway anchor with `download` set.
Future<bool> deliverPdf(String filename, Uint8List bytes) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}
```

`lib/core/pdf/report_pdf.dart`:
```dart
/// One column of a [ReportPdf] table.
class ReportPdfColumn {
  const ReportPdfColumn(this.header, {this.numeric = false, this.flex = 1});

  final String header;

  /// Right-aligned when true.
  final bool numeric;

  /// Relative width.
  final double flex;
}

/// A tabular report ready to lay out: already formatted strings, one per
/// cell. Built by lib/features/finance/finance_pdf.dart, rendered by
/// lib/core/pdf/report_pdf_renderer.dart.
class ReportPdf {
  const ReportPdf({
    required this.title,
    required this.resortName,
    required this.gstinLabel,
    required this.periodLabel,
    required this.fileName,
    required this.columns,
    required this.rows,
    this.totals,
    this.notes = const [],
    this.emptyMessage = 'Nothing to report in this period.',
  });

  final String title;
  final String resortName;

  /// `GSTIN 29ABCDE1234F1Z5` or `GSTIN not set`.
  final String gstinLabel;

  /// `1 Aug 2026 – 31 Aug 2026`.
  final String periodLabel;
  final String fileName;
  final List<ReportPdfColumn> columns;

  /// Every row has exactly `columns.length` cells.
  final List<List<String>> rows;

  /// A bold last row, or none.
  final List<String>? totals;

  /// Lines printed under the table.
  final List<String> notes;

  /// Printed instead of the table when [rows] is empty.
  final String emptyMessage;
}
```

- [ ] **Step 6: Implement the invoice models**

`lib/data/models/invoice.dart`:
```dart
import 'current_charges.dart';
import 'payment_method.dart';
import 'reservation.dart';

/// The resort block of an invoice, from the `properties` embed. Null in
/// [InvoiceInput.resort] when RLS hides the row (a guest of a resort that
/// is no longer active).
class InvoiceResort {
  const InvoiceResort({
    required this.name,
    required this.slug,
    this.address,
    this.gstin,
  });

  final String name;
  final String slug;
  final String? address;
  final String? gstin;
}

/// One non-cancelled food order or activity booking: its tax-inclusive
/// amount and the tax stored on it (P4's `tax_amount`/`tax_pct`; 0 and null
/// on rows from before P4).
class InvoiceCharge {
  const InvoiceCharge({required this.amount, this.taxAmount = 0, this.taxPct});

  final num amount;
  final num taxAmount;
  final num? taxPct;
}

/// `public.payment_kind`.
enum InvoicePaymentKind {
  advance('Advance'),
  balance('Balance');

  const InvoicePaymentKind(this.label);
  final String label;

  static InvoicePaymentKind fromWire(String raw) =>
      raw == 'advance' ? advance : balance;
}

/// One succeeded payment as printed on the invoice.
class InvoicePayment {
  const InvoicePayment({
    required this.kind,
    required this.amount,
    required this.method,
    this.reference,
    required this.paidAt,
  });

  final InvoicePaymentKind kind;
  final num amount;
  final PaymentMethod method;

  /// The receipt/UTR typed at the desk, or the gateway's payment id for an
  /// online payment. Null when blank.
  final String? reference;
  final DateTime paidAt;
}

/// Everything `buildInvoice` needs, as read from the server.
class InvoiceInput {
  const InvoiceInput({
    required this.reservation,
    required this.resort,
    required this.unitName,
    required this.dayUse,
    required this.food,
    required this.activities,
    required this.payments,
    required this.charges,
    required this.now,
  });

  /// With `customerName` from the `profiles` embed.
  final Reservation reservation;
  final InvoiceResort? resort;
  final String? unitName;

  /// A slot booking (`reservations.slot_type_id` set).
  final bool dayUse;
  final List<InvoiceCharge> food;
  final List<InvoiceCharge> activities;
  final List<InvoicePayment> payments;
  final CurrentCharges charges;

  /// The provisional bill's date.
  final DateTime now;
}

enum InvoiceLineKind { room, cleaningFee, coupon, foodDrink, spaActivities }

/// One charge line: [amount] excludes tax, [tax] is the tax on it.
class InvoiceLine {
  const InvoiceLine({
    required this.kind,
    required this.label,
    required this.amount,
    this.tax = 0,
    this.taxPct,
  });

  final InvoiceLineKind kind;
  final String label;
  final num amount;
  final num tax;

  /// Shown next to the tax; null when there is no single rate.
  final num? taxPct;

  num get total => amount + tax;
}

/// A booking invoice ready to lay out. Built only by `buildInvoice`, which
/// guarantees [total] equals `current_charges.total`.
class Invoice {
  const Invoice({
    required this.number,
    required this.provisional,
    required this.issuedAt,
    required this.resortName,
    this.resortAddress,
    this.gstin,
    required this.guestName,
    this.unitName,
    required this.stayStart,
    required this.stayEnd,
    this.guests,
    required this.lines,
    required this.payments,
    required this.paid,
    required this.amountDue,
    this.notes = const [],
  });

  /// `PASALA-3F2A9C1B`.
  final String number;

  /// A checked-in stay's running bill rather than the final invoice.
  final bool provisional;
  final DateTime issuedAt;
  final String resortName;
  final String? resortAddress;
  final String? gstin;
  final String guestName;
  final String? unitName;
  final DateTime stayStart;
  final DateTime stayEnd;
  final int? guests;
  final List<InvoiceLine> lines;

  /// Oldest first.
  final List<InvoicePayment> payments;

  /// `current_charges.paid`.
  final num paid;

  /// `current_charges.balance`.
  final num amountDue;
  final List<String> notes;

  String get title => provisional ? 'Provisional bill' : 'Invoice';
  String get fileName => 'invoice-$number.pdf';
  num get subtotal => lines.fold<num>(0, (a, l) => a + l.amount);
  num get taxTotal => lines.fold<num>(0, (a, l) => a + l.tax);
  num get total => lines.fold<num>(0, (a, l) => a + l.total);
  num get advancePaid => payments
      .where((p) => p.kind == InvoicePaymentKind.advance)
      .fold<num>(0, (a, p) => a + p.amount);
}
```

- [ ] **Step 7: Add the two seams with stub implementations**

`lib/core/pdf/pdf_exporter.dart` (Task 4 replaces the stub bodies):
```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import 'report_pdf.dart';

/// Turns an [Invoice] or a [ReportPdf] into PDF bytes. Tests override
/// [pdfExporterProvider] with `FakePdfExporter`.
abstract class PdfExporter {
  Future<Uint8List> invoice(Invoice invoice);
  Future<Uint8List> report(ReportPdf report);
}

class PasalaPdfExporter implements PdfExporter {
  @override
  Future<Uint8List> invoice(Invoice invoice) =>
      throw UnimplementedError('PasalaPdfExporter.invoice lands in P2 Task 4');

  @override
  Future<Uint8List> report(ReportPdf report) =>
      throw UnimplementedError('PasalaPdfExporter.report lands in P2 Task 4');
}

final pdfExporterProvider = Provider<PdfExporter>((ref) => PasalaPdfExporter());
```

`lib/data/repositories/invoice_repository.dart` (Task 3 replaces the stub body):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../models/invoice.dart';

/// The slice of [InvoiceRepository] the invoice button needs. Tests
/// override [invoiceSourceProvider] with `FakeInvoiceSource`.
abstract class InvoiceSource {
  /// The invoice of [reservationId], read afresh on every call. Throws a
  /// `BookingFailure`: the server's refusal, or `InvalidState` from
  /// `buildInvoice`.
  Future<Invoice> invoice(String reservationId);
}

class InvoiceRepository implements InvoiceSource {
  InvoiceRepository(this._db);

  // ignore: unused_field
  final SupabaseClient _db;

  @override
  Future<Invoice> invoice(String reservationId) =>
      throw UnimplementedError('InvoiceRepository.invoice lands in P2 Task 3');
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(supabaseProvider)),
);

/// The [InvoiceSource] seam every screen calls through.
final invoiceSourceProvider = Provider<InvoiceSource>(
  (ref) => ref.watch(invoiceRepositoryProvider),
);
```

- [ ] **Step 8: Add the test fakes**

`test/support/fake_pdf_exporter.dart`:
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/core/pdf/report_pdf.dart';
import 'package:pasala/data/models/invoice.dart';

/// Records what a screen asked to render and answers [bytes]. Set [error]
/// to make every call throw, [hold] to keep calls pending.
class FakePdfExporter implements PdfExporter {
  static final Uint8List bytes = Uint8List.fromList('%PDF-1.7 fake'.codeUnits);

  final List<Invoice> invoices = [];
  final List<ReportPdf> reports = [];
  Object? error;
  Completer<void>? hold;

  Future<Uint8List> _answer() async {
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return bytes;
  }

  @override
  Future<Uint8List> invoice(Invoice invoice) {
    invoices.add(invoice);
    return _answer();
  }

  @override
  Future<Uint8List> report(ReportPdf report) {
    reports.add(report);
    return _answer();
  }
}

/// A [PdfDeliverer] stand-in: records every file, answers [delivers].
class PdfDeliveries {
  PdfDeliveries({this.delivers = true});

  final bool delivers;
  final List<(String, Uint8List)> files = [];

  Future<bool> deliver(String filename, Uint8List bytes) async {
    files.add((filename, bytes));
    return delivers;
  }
}
```

`test/support/fake_invoice_source.dart`:
```dart
import 'dart:async';

import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';

/// In-memory [InvoiceSource]: answers [value], or throws [error]; [hold]
/// keeps calls pending; [calls] lists the reservation ids asked for.
class FakeInvoiceSource implements InvoiceSource {
  Invoice value = sampleInvoice();
  Object? error;
  Completer<void>? hold;
  final List<String> calls = [];

  @override
  Future<Invoice> invoice(String reservationId) async {
    calls.add(reservationId);
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return value;
  }
}

/// Resort R's invoice for a 2-night stay: ₹10,000 room + ₹500 cleaning,
/// coupon SAVE10 (−₹1,000), 12% room tax (₹1,080 + ₹60), food ₹840 incl.
/// ₹40 tax at 5%, spa ₹1,180 incl. ₹180 tax at 18% — total ₹12,660, paid
/// ₹3,192 online in advance and ₹9,468 in cash at checkout.
Invoice sampleInvoice({
  bool provisional = false,
  String number = 'FIN-R-3F2A9C1B',
  String guestName = 'Gita Guest',
  List<InvoiceLine>? lines,
  List<InvoicePayment>? payments,
  num paid = 12660,
  num amountDue = 0,
  List<String> notes = const [],
}) =>
    Invoice(
      number: number,
      provisional: provisional,
      issuedAt: DateTime(2026, 8, 12, 11),
      resortName: 'Resort R',
      resortAddress: '12 Lake Road, Coorg',
      gstin: '29ABCDE1234F1Z5',
      guestName: guestName,
      unitName: 'Cottage 1',
      stayStart: DateTime(2026, 8, 10, 14),
      stayEnd: DateTime(2026, 8, 12, 11),
      guests: 2,
      lines: lines ??
          const [
            InvoiceLine(
                kind: InvoiceLineKind.room,
                label: 'Room (2 nights)',
                amount: 10000,
                tax: 1080,
                taxPct: 12),
            InvoiceLine(
                kind: InvoiceLineKind.cleaningFee,
                label: 'Cleaning fee',
                amount: 500,
                tax: 60,
                taxPct: 12),
            InvoiceLine(
                kind: InvoiceLineKind.coupon,
                label: 'Coupon (SAVE10)',
                amount: -1000),
            InvoiceLine(
                kind: InvoiceLineKind.foodDrink,
                label: 'Food & Drink',
                amount: 800,
                tax: 40,
                taxPct: 5),
            InvoiceLine(
                kind: InvoiceLineKind.spaActivities,
                label: 'Spa & Activities',
                amount: 1000,
                tax: 180,
                taxPct: 18),
          ],
      payments: payments ??
          [
            InvoicePayment(
                kind: InvoicePaymentKind.advance,
                amount: 3192,
                method: PaymentMethod.gateway,
                reference: 'mock_abc',
                paidAt: DateTime(2026, 8, 1, 9)),
            InvoicePayment(
                kind: InvoicePaymentKind.balance,
                amount: 9468,
                method: PaymentMethod.cash,
                reference: 'R-17',
                paidAt: DateTime(2026, 8, 12, 11)),
          ],
      paid: paid,
      amountDue: amountDue,
      notes: notes,
    );
```

- [ ] **Step 9: Run the tests to see them pass**

Run: `flutter test test/core/pdf test/data/invoice_test.dart`
Expected: PASS (8 tests). If `supports(0x20B9)` fails, the downloaded file is not Noto Sans 2.x — re-download from the jsDelivr mirror in Step 2; do not change the currency symbol.

Run: `flutter analyze`
Expected: only the 2 baseline infos in `service_request_screen.dart`.

- [ ] **Step 10: Format the new files and commit**

```bash
dart format lib/core/pdf lib/data/models/invoice.dart lib/data/repositories/invoice_repository.dart test/support/pdf_test_fonts.dart test/support/fake_pdf_exporter.dart test/support/fake_invoice_source.dart test/core/pdf test/data/invoice_test.dart
git add pubspec.yaml pubspec.lock assets/fonts lib/core/pdf lib/data/models/invoice.dart lib/data/repositories/invoice_repository.dart test/support/pdf_test_fonts.dart test/support/fake_pdf_exporter.dart test/support/fake_invoice_source.dart test/core/pdf test/data/invoice_test.dart
git commit -m "feat(pdf): pdf/printing, bundled fonts, invoice and report PDF contracts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
(`lib/core/pdf` holds only files created in this task, so formatting the directory touches no pre-existing file.)

---

### Task 2: `buildInvoice` — the invoice rules

**Files:**
- Create: `lib/data/models/invoice_builder.dart`
- Test: `test/data/invoice_builder_test.dart`

**Interfaces:**
- Consumes: Task 1 invoice models; `InvalidState` (`lib/core/errors.dart`); `Reservation`, `ReservationKind`, `ReservationStatus`; `Quote`, `QuoteLine`, `AppliedCoupon` (`lib/data/models/quote.dart`); `CurrentCharges`.
- Produces: `String invoiceNumber(String slug, String reservationId)`; `Invoice buildInvoice(InvoiceInput input)` — throws `InvalidState` with the spec's messages.

- [ ] **Step 1: Write the failing tests**

`test/data/invoice_builder_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/invoice_builder.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';

const _id = '3f2a9c1b-0000-4000-8000-000000000001';
const _resort = InvoiceResort(
  name: 'Resort R',
  slug: 'fin-r',
  address: '12 Lake Road, Coorg',
  gstin: '29ABCDE1234F1Z5',
);
const _save10 =
    AppliedCoupon(code: 'SAVE10', kind: 'fixed', value: 1000, discount: 1000);

/// A stored quote as get_quote builds it: tax on subtotal + cleaning fee −
/// discount, total = that + tax.
Quote _quote({
  num subtotal = 10000,
  num cleaningFee = 500,
  AppliedCoupon? coupon = _save10,
  num taxPct = 12,
  int nights = 2,
}) {
  final discount = coupon?.discount ?? 0;
  final tax = (subtotal + cleaningFee - discount) * taxPct / 100;
  return Quote(
    currency: 'INR',
    guests: 2,
    lines: [
      for (var i = 0; i < nights; i++)
        QuoteLine(
          date: DateTime.utc(2026, 8, 10 + i),
          label: 'Weekday rate',
          amount: subtotal / nights,
          extraGuests: 0,
          extraGuestAmount: 0,
        ),
    ],
    subtotal: subtotal,
    cleaningFee: cleaningFee,
    coupon: coupon,
    taxPct: taxPct,
    taxAmount: tax,
    total: subtotal + cleaningFee - discount + tax,
  );
}

final _checkedOutAt = DateTime.utc(2026, 8, 12, 5, 30);
final _now = DateTime.utc(2026, 8, 11, 12);

Reservation _reservation({
  ReservationStatus status = ReservationStatus.checkedOut,
  ReservationKind kind = ReservationKind.booking,
  Quote? quote,
  String? customerName = 'Gita Guest',
}) =>
    Reservation(
      id: _id,
      unitId: 'u1',
      start: DateTime.utc(2026, 8, 10, 8, 30),
      end: DateTime.utc(2026, 8, 12, 5, 30),
      kind: kind,
      status: status,
      customerId: 'g1',
      customerName: customerName,
      guests: 2,
      quote: quote ?? _quote(),
      checkedOutAt:
          status == ReservationStatus.checkedOut ? _checkedOutAt : null,
    );

final _advance = InvoicePayment(
  kind: InvoicePaymentKind.advance,
  amount: 3192,
  method: PaymentMethod.gateway,
  reference: 'mock_abc',
  paidAt: DateTime.utc(2026, 8, 1, 4),
);
final _balance = InvoicePayment(
  kind: InvoicePaymentKind.balance,
  amount: 9468,
  method: PaymentMethod.cash,
  reference: 'R-17',
  paidAt: DateTime.utc(2026, 8, 12, 5),
);

const _food = [
  InvoiceCharge(amount: 525, taxAmount: 25, taxPct: 5),
  InvoiceCharge(amount: 315, taxAmount: 15, taxPct: 5),
];
const _spa = [InvoiceCharge(amount: 1180, taxAmount: 180, taxPct: 18)];

InvoiceInput _input({
  Reservation? reservation,
  InvoiceResort? resort = _resort,
  String? unitName = 'Cottage 1',
  bool dayUse = false,
  List<InvoiceCharge> food = _food,
  List<InvoiceCharge> activities = _spa,
  List<InvoicePayment>? payments,
  double total = 12660,
  double paid = 12660,
  double balance = 0,
}) =>
    InvoiceInput(
      reservation: reservation ?? _reservation(),
      resort: resort,
      unitName: unitName,
      dayUse: dayUse,
      food: food,
      activities: activities,
      // Newest first on purpose: the invoice must sort them.
      payments: payments ?? [_balance, _advance],
      charges: CurrentCharges(
        stayAmount: 10640,
        foodAmount: 840,
        activityAmount: 1180,
        total: total,
        paid: paid,
        balance: balance,
      ),
      now: _now,
    );

Matcher _refusal(String message) =>
    throwsA(isA<InvalidState>().having((e) => e.message, 'message', message));

void main() {
  test('itemises room, cleaning fee, coupon, food and spa with tax per category',
      () {
    final invoice = buildInvoice(_input());
    expect(
      invoice.lines.map((l) => (l.kind, l.label, l.amount, l.tax, l.taxPct)),
      [
        (InvoiceLineKind.room, 'Room (2 nights)', 10000, 1080, 12),
        (InvoiceLineKind.cleaningFee, 'Cleaning fee', 500, 60, 12),
        (InvoiceLineKind.coupon, 'Coupon (SAVE10)', -1000, 0, null),
        (InvoiceLineKind.foodDrink, 'Food & Drink', 800, 40, 5),
        (InvoiceLineKind.spaActivities, 'Spa & Activities', 1000, 180, 18),
      ],
    );
    expect(invoice.subtotal, 11300);
    expect(invoice.taxTotal, 1360);
    expect(invoice.total, 12660);
    expect(invoice.paid, 12660);
    expect(invoice.amountDue, 0);
    expect(invoice.advancePaid, 3192);
    expect(invoice.resortName, 'Resort R');
    expect(invoice.resortAddress, '12 Lake Road, Coorg');
    expect(invoice.gstin, '29ABCDE1234F1Z5');
    expect(invoice.guestName, 'Gita Guest');
    expect(invoice.unitName, 'Cottage 1');
    expect(invoice.guests, 2);
  });

  test('numbers the invoice from the resort slug and the reservation id', () {
    expect(buildInvoice(_input()).number, 'FIN-R-3F2A9C1B');
    expect(invoiceNumber('pasala', 'ab-cd'), 'PASALA-ABCD');
  });

  test('a checked-out booking is an Invoice dated at checkout', () {
    final invoice = buildInvoice(_input());
    expect(invoice.provisional, isFalse);
    expect(invoice.title, 'Invoice');
    expect(invoice.issuedAt, _checkedOutAt);
    expect(invoice.notes, [
      'Tax is charged on the room and cleaning fee after the coupon discount.',
    ]);
  });

  test('a checked-in booking is a provisional bill dated now', () {
    final invoice = buildInvoice(_input(
      reservation: _reservation(status: ReservationStatus.checkedIn),
    ));
    expect(invoice.provisional, isTrue);
    expect(invoice.issuedAt, _now);
    expect(invoice.notes,
        contains('The stay is still in progress, so this bill may change before checkout.'));
  });

  for (final status in [
    ReservationStatus.hold,
    ReservationStatus.pendingPayment,
    ReservationStatus.confirmed,
    ReservationStatus.cancelled,
  ]) {
    test('refuses a ${status.name} booking', () {
      expect(
        () => buildInvoice(_input(reservation: _reservation(status: status))),
        _refusal('An invoice is available once the guest has checked in.'),
      );
    });
  }

  test('refuses admin blocks and OTA rows', () {
    for (final kind in [ReservationKind.block, ReservationKind.ota]) {
      expect(
        () => buildInvoice(_input(reservation: _reservation(kind: kind))),
        _refusal('Only guest bookings have an invoice.'),
      );
    }
  });

  test('refuses when the resort cannot be read', () {
    expect(
      () => buildInvoice(_input(resort: null)),
      _refusal("This resort isn't taking bookings right now, so its invoice "
          "can't be issued. Contact the resort."),
    );
  });

  test('refuses a bill that changed between reads', () {
    expect(
      () => buildInvoice(_input(total: 13000)),
      _refusal('The bill changed while the invoice was being prepared. Try again.'),
    );
  });

  test('tolerates paise of float noise against current_charges', () {
    expect(buildInvoice(_input(total: 12660.004)).total, 12660);
  });

  test('rows without stored tax (before P4) count as untaxed', () {
    final invoice = buildInvoice(_input(
      food: const [InvoiceCharge(amount: 840)],
      activities: const [InvoiceCharge(amount: 1180)],
      total: 12660,
    ));
    final food = invoice.lines.firstWhere((l) => l.kind == InvoiceLineKind.foodDrink);
    expect((food.amount, food.tax, food.taxPct), (840, 0, null));
  });

  test('shows a category rate only when every row shares it', () {
    final invoice = buildInvoice(_input(food: const [
      InvoiceCharge(amount: 525, taxAmount: 25, taxPct: 5),
      InvoiceCharge(amount: 315, taxAmount: 48.05, taxPct: 18),
    ]));
    final food = invoice.lines.firstWhere((l) => l.kind == InvoiceLineKind.foodDrink);
    expect(food.taxPct, isNull);
    expect(food.tax, 73.05);
    expect(food.amount, 766.95);
  });

  test('no coupon, no cleaning fee, nothing ordered: a single room line', () {
    final invoice = buildInvoice(_input(
      reservation: _reservation(
          quote: _quote(subtotal: 7000, cleaningFee: 0, coupon: null, taxPct: 0)),
      food: const [],
      activities: const [],
      total: 7000,
    ));
    expect(invoice.lines.map((l) => (l.label, l.amount, l.tax, l.taxPct)),
        [('Room (2 nights)', 7000, 0, null)]);
    expect(invoice.notes, isEmpty);
  });

  test('a slot booking is day use, one night is singular', () {
    expect(buildInvoice(_input(dayUse: true)).lines.first.label, 'Room (day use)');
    final oneNight = buildInvoice(_input(
      reservation: _reservation(
          quote: _quote(subtotal: 5000, cleaningFee: 0, coupon: null, taxPct: 0, nights: 1)),
      food: const [],
      activities: const [],
      total: 5000,
    ));
    expect(oneNight.lines.single.label, 'Room (1 night)');
  });

  test('a blank guest name prints as Guest', () {
    for (final name in [null, '', '   ']) {
      expect(buildInvoice(_input(reservation: _reservation(customerName: name))).guestName,
          'Guest');
    }
  });

  test('payments are listed oldest first', () {
    final invoice = buildInvoice(_input());
    expect(invoice.payments.map((p) => p.kind),
        [InvoicePaymentKind.advance, InvoicePaymentKind.balance]);
  });

  test('a blank address or GSTIN becomes null', () {
    final invoice = buildInvoice(_input(
      resort: const InvoiceResort(name: 'Resort R', slug: 'fin-r', address: '  ', gstin: ''),
    ));
    expect(invoice.resortAddress, isNull);
    expect(invoice.gstin, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/data/invoice_builder_test.dart`
Expected: FAIL — `invoice_builder.dart` not found.

- [ ] **Step 3: Implement the builder**

`lib/data/models/invoice_builder.dart`:
```dart
import 'dart:math' as math;

import '../../core/errors.dart';
import 'invoice.dart';
import 'reservation.dart';

/// `pasala` + `3f2a9c1b-…` -> `PASALA-3F2A9C1B`: the same for every viewer,
/// from stored ids only.
String invoiceNumber(String slug, String reservationId) {
  final hex = reservationId.replaceAll('-', '');
  final short = hex.length >= 8 ? hex.substring(0, 8) : hex;
  return '${slug.toUpperCase()}-${short.toUpperCase()}';
}

num _r2(num v) => (v * 100).round() / 100;
num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);
String? _blankToNull(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

/// The rate every row shares, or null (none, mixed, or zero).
num? _uniformPct(List<InvoiceCharge> rows) {
  final pcts = rows.map((r) => r.taxPct).toSet();
  if (pcts.length != 1) return null;
  final pct = pcts.single;
  return (pct == null || pct == 0) ? null : pct;
}

String _roomLabel(InvoiceInput input) {
  if (input.dayUse) return 'Room (day use)';
  final nights = input.reservation.quote!.lines.length;
  return 'Room ($nights ${nights == 1 ? 'night' : 'nights'})';
}

/// Builds the invoice of [input] (spec Decisions 3–7, 11). Never
/// recomputes a price: room figures come from the stored quote, food and
/// activities from their rows, and the lines must add up to
/// `current_charges.total` or the invoice is refused.
Invoice buildInvoice(InvoiceInput input) {
  final r = input.reservation;
  if (r.kind != ReservationKind.booking) {
    throw const InvalidState('Only guest bookings have an invoice.');
  }
  final provisional = switch (r.status) {
    ReservationStatus.checkedOut => false,
    ReservationStatus.checkedIn => true,
    _ => throw const InvalidState(
        'An invoice is available once the guest has checked in.'),
  };
  final resort = input.resort;
  if (resort == null) {
    throw const InvalidState("This resort isn't taking bookings right now, "
        "so its invoice can't be issued. Contact the resort.");
  }

  final lines = <InvoiceLine>[];
  final notes = <String>[];
  final q = r.quote;
  if (q != null) {
    // The same split report_ledger (0048) makes: the room line is taxed on
    // subtotal minus the part of the discount it absorbs; the cleaning fee
    // carries the rest of the quote's tax, so the two add up exactly.
    final discount = q.coupon?.discount ?? 0;
    final roomDiscount = math.min(discount, q.subtotal);
    final roomTax = _r2((q.subtotal - roomDiscount) * q.taxPct / 100);
    final cleaningTax = _r2(q.taxAmount - roomTax);
    final pct = q.taxPct == 0 ? null : q.taxPct;
    lines.add(InvoiceLine(
      kind: InvoiceLineKind.room,
      label: _roomLabel(input),
      amount: q.subtotal,
      tax: roomTax,
      taxPct: pct,
    ));
    if (q.cleaningFee != 0 || cleaningTax != 0) {
      lines.add(InvoiceLine(
        kind: InvoiceLineKind.cleaningFee,
        label: 'Cleaning fee',
        amount: q.cleaningFee,
        tax: cleaningTax,
        taxPct: pct,
      ));
    }
    if (q.coupon != null) {
      lines.add(InvoiceLine(
        kind: InvoiceLineKind.coupon,
        label: 'Coupon (${q.coupon!.code})',
        amount: -discount,
      ));
      if (q.taxAmount != 0) {
        notes.add(
            'Tax is charged on the room and cleaning fee after the coupon discount.');
      }
    }
  }

  // Food and activity prices include their tax (P4).
  void addCategory(InvoiceLineKind kind, String label, List<InvoiceCharge> rows) {
    if (rows.isEmpty) return;
    final gross = _sum(rows.map((c) => c.amount));
    final tax = _sum(rows.map((c) => c.taxAmount));
    lines.add(InvoiceLine(
      kind: kind,
      label: label,
      amount: _r2(gross - tax),
      tax: _r2(tax),
      taxPct: _uniformPct(rows),
    ));
  }

  addCategory(InvoiceLineKind.foodDrink, 'Food & Drink', input.food);
  addCategory(InvoiceLineKind.spaActivities, 'Spa & Activities', input.activities);

  final total = _sum(lines.map((l) => l.total));
  if ((total - input.charges.total).abs() > 0.01) {
    throw const InvalidState(
        'The bill changed while the invoice was being prepared. Try again.');
  }

  if (provisional) {
    notes.add('The stay is still in progress, so this bill may change before checkout.');
  }

  final payments = [...input.payments]
    ..sort((a, b) => a.paidAt.compareTo(b.paidAt));

  return Invoice(
    number: invoiceNumber(resort.slug, r.id),
    provisional: provisional,
    issuedAt: provisional ? input.now : (r.checkedOutAt ?? input.now),
    resortName: resort.name,
    resortAddress: _blankToNull(resort.address),
    gstin: _blankToNull(resort.gstin),
    guestName: _blankToNull(r.customerName) ?? 'Guest',
    unitName: _blankToNull(input.unitName),
    stayStart: r.start,
    stayEnd: r.end,
    guests: r.guests,
    lines: lines,
    payments: payments,
    paid: input.charges.paid,
    amountDue: input.charges.balance,
    notes: notes,
  );
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/data/invoice_builder_test.dart`
Expected: PASS (all tests). If "shows a category rate only when every row shares it" fails on `766.95`/`73.05` by float noise, compare with `closeTo(…, 0.001)` in that one test — the builder already rounds with `_r2`.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze
dart format lib/data/models/invoice_builder.dart test/data/invoice_builder_test.dart
git add lib/data/models/invoice_builder.dart test/data/invoice_builder_test.dart
git commit -m "feat(invoice): build invoices from the stored quote, rows and current_charges

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected analyze output: the 2 baseline infos only.

---

### Task 3: `InvoiceRepository` — reading an invoice from Supabase

**Files:**
- Modify: `lib/data/repositories/invoice_repository.dart` (replace the Task 1 stub body)
- Test: `test/data/invoice_repository_test.dart`

**Interfaces:**
- Consumes: `buildInvoice` (Task 2); invoice models (Task 1); `Reservation.fromJson`; `CurrentCharges.fromJson`; `PaymentMethod.fromWire`; `mapPostgrestError`.
- Produces: `InvoiceRepository(SupabaseClient db, {DateTime Function()? clock})`; `static const String reservationSelect`; `static InvoiceInput inputFrom({required Map<String, dynamic> reservationRow, required List<dynamic> foodRows, required List<dynamic> activityRows, required List<dynamic> paymentRows, required Map<String, dynamic> chargesJson, required DateTime now})`; `Future<Invoice> invoice(String reservationId)`. `invoiceRepositoryProvider`/`invoiceSourceProvider` unchanged.

- [ ] **Step 1: Write the failing tests**

`test/data/invoice_repository_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/invoice.dart';
import 'package:pasala/data/models/invoice_builder.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';

const _id = '3f2a9c1b-0000-4000-8000-000000000001';
const _props = {
  'name': 'Resort R',
  'slug': 'fin-r',
  'address': '12 Lake Road, Coorg',
  'gstin': '29ABCDE1234F1Z5',
};

Map<String, dynamic> _quoteJson() => {
      'currency': 'INR',
      'guests': 2,
      'lines': [
        {'date': '2026-08-10', 'label': 'Weekday rate', 'amount': 5000, 'extra_guests': 0, 'extra_guest_amount': 0},
        {'date': '2026-08-11', 'label': 'Weekday rate', 'amount': 5000, 'extra_guests': 0, 'extra_guest_amount': 0},
      ],
      'subtotal': 10000,
      'cleaning_fee': 500,
      'coupon': {'code': 'SAVE10', 'kind': 'fixed', 'value': 1000, 'discount': 1000},
      'tax_pct': 12,
      'tax_amount': 1140,
      'total': 10640,
    };

/// A reservations row as `InvoiceRepository.reservationSelect` returns it.
Map<String, dynamic> _row({
  Map<String, dynamic>? properties = _props,
  Map<String, dynamic>? units = const {'name': 'Cottage 1'},
  String? slotTypeId,
}) =>
    {
      'id': _id,
      'unit_id': 'u1',
      'property_id': 'p1',
      'period': '["2026-08-10 08:30:00+00","2026-08-12 05:30:00+00")',
      'kind': 'booking',
      'status': 'checked_out',
      'customer_id': 'g1',
      'guests': 2,
      'quote': _quoteJson(),
      'slot_type_id': slotTypeId,
      'checked_in_at': '2026-08-10T08:40:00+00:00',
      'checked_out_at': '2026-08-12T05:30:00+00:00',
      'created_at': '2026-08-01T04:00:00+00:00',
      'properties': properties,
      'units': units,
      'profiles': {'full_name': 'Gita Guest', 'phone': '9800000000'},
    };

final _food = [
  {'id': 'f1', 'total': 525, 'status': 'delivered', 'tax_amount': 25, 'tax_pct': 5},
  {'id': 'f2', 'total': 315, 'status': 'placed', 'tax_amount': 15, 'tax_pct': 5},
];
final _activities = [
  {'id': 'a1', 'amount': 1180, 'status': 'booked', 'tax_amount': 180, 'tax_pct': 18},
];
final _payments = [
  {'amount': 3192, 'kind': 'advance', 'method': 'gateway', 'reference': null, 'gateway_ref': 'mock_abc', 'created_at': '2026-08-01T04:00:00+00:00'},
  {'amount': 9468, 'kind': 'balance', 'method': 'cash', 'reference': ' R-17 ', 'gateway_ref': 'desk-$_id', 'created_at': '2026-08-12T05:30:00+00:00'},
];
const _charges = {
  'stay_amount': 10640,
  'food_amount': 840,
  'activity_amount': 1180,
  'total': 12660,
  'paid': 12660,
  'balance': 0,
};

InvoiceInput _parse({
  Map<String, dynamic>? row,
  List<dynamic>? food,
  List<dynamic>? activities,
  List<dynamic>? payments,
}) =>
    InvoiceRepository.inputFrom(
      reservationRow: row ?? _row(),
      foodRows: food ?? _food,
      activityRows: activities ?? _activities,
      paymentRows: payments ?? _payments,
      chargesJson: _charges,
      now: DateTime.utc(2026, 9, 25),
    );

void main() {
  test('selects the resort, unit and guest embeds it parses', () {
    expect(
      InvoiceRepository.reservationSelect,
      '*, properties(name, slug, address, gstin), units(name), '
      'profiles!reservations_customer_id_fkey(full_name, phone)',
    );
  });

  test('parses the reservation, the resort, the unit and the guest', () {
    final input = _parse();
    expect(input.reservation.id, _id);
    expect(input.reservation.customerName, 'Gita Guest');
    expect(input.reservation.quote!.subtotal, 10000);
    expect(input.resort!.name, 'Resort R');
    expect(input.resort!.slug, 'fin-r');
    expect(input.resort!.address, '12 Lake Road, Coorg');
    expect(input.resort!.gstin, '29ABCDE1234F1Z5');
    expect(input.unitName, 'Cottage 1');
    expect(input.dayUse, isFalse);
    expect(input.charges.total, 12660);
    expect(input.now, DateTime.utc(2026, 9, 25));
  });

  test('a resort hidden by RLS parses as no resort', () {
    final input = _parse(row: _row(properties: null, units: null));
    expect(input.resort, isNull);
    expect(input.unitName, isNull);
  });

  test('a slot booking is day use', () {
    expect(_parse(row: _row(slotTypeId: 'st1')).dayUse, isTrue);
  });

  test('food and activity rows carry their stored tax when present', () {
    final input = _parse(food: [
      ..._food,
      {'id': 'f3', 'total': 300, 'status': 'placed'}, // before P4: no tax columns
    ]);
    expect(input.food.map((c) => (c.amount, c.taxAmount, c.taxPct)),
        [(525, 25, 5), (315, 15, 5), (300, 0, null)]);
    expect(input.activities.single.taxAmount, 180);
  });

  test('online payments show the gateway id; desk payments the typed reference', () {
    final input = _parse(payments: [
      ..._payments,
      {'amount': 1, 'kind': 'balance', 'method': 'card', 'reference': '  ', 'gateway_ref': 'desk-x', 'created_at': '2026-08-12T06:00:00+00:00'},
    ]);
    expect(input.payments.map((p) => (p.kind, p.method, p.reference)), [
      (InvoicePaymentKind.advance, PaymentMethod.gateway, 'mock_abc'),
      (InvoicePaymentKind.balance, PaymentMethod.cash, 'R-17'),
      (InvoicePaymentKind.balance, PaymentMethod.card, null),
    ]);
    expect(input.payments.first.paidAt, DateTime.utc(2026, 8, 1, 4));
  });

  test('the parsed rows build the expected invoice', () {
    final invoice = buildInvoice(_parse());
    expect(invoice.number, 'FIN-R-3F2A9C1B');
    expect(invoice.total, 12660);
    expect(invoice.amountDue, 0);
  });
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/data/invoice_repository_test.dart`
Expected: FAIL — `reservationSelect` and `inputFrom` are not defined.

- [ ] **Step 3: Implement the repository**

Replace `lib/data/repositories/invoice_repository.dart` with:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/current_charges.dart';
import '../models/invoice.dart';
import '../models/invoice_builder.dart';
import '../models/payment_method.dart';
import '../models/reservation.dart';

/// The slice of [InvoiceRepository] the invoice button needs. Tests
/// override [invoiceSourceProvider] with `FakeInvoiceSource`.
abstract class InvoiceSource {
  /// The invoice of [reservationId], read afresh on every call. Throws a
  /// `BookingFailure`: the server's refusal, or `InvalidState` from
  /// `buildInvoice`.
  Future<Invoice> invoice(String reservationId);
}

/// Reads an invoice with the viewer's own rights -- no new SQL: the
/// reservation and its resort/unit/guest embeds, its non-cancelled food
/// orders and activity bookings, its succeeded payments (all under the RLS
/// of 0044_resort_policies.sql: the guest who owns it, or staff of its
/// resort) and `current_charges`, which applies the same rule.
class InvoiceRepository implements InvoiceSource {
  InvoiceRepository(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final SupabaseClient _db;
  final DateTime Function() _clock;

  static const reservationSelect =
      '*, properties(name, slug, address, gstin), units(name), '
      'profiles!reservations_customer_id_fkey(full_name, phone)';

  @override
  Future<Invoice> invoice(String reservationId) async {
    try {
      final results = await Future.wait<Object?>([
        _db
            .from('reservations')
            .select(reservationSelect)
            .eq('id', reservationId)
            .single(),
        _db
            .from('food_orders')
            .select()
            .eq('reservation_id', reservationId)
            .neq('status', 'cancelled'),
        _db
            .from('activity_bookings')
            .select()
            .eq('reservation_id', reservationId)
            .neq('status', 'cancelled'),
        _db
            .from('payments')
            .select('amount, kind, method, reference, gateway_ref, created_at')
            .eq('reservation_id', reservationId)
            .eq('status', 'succeeded')
            .order('created_at', ascending: true),
        _db.rpc('current_charges', params: {'p_reservation_id': reservationId}),
      ]);
      return buildInvoice(inputFrom(
        reservationRow: results[0]! as Map<String, dynamic>,
        foodRows: results[1]! as List<dynamic>,
        activityRows: results[2]! as List<dynamic>,
        paymentRows: results[3]! as List<dynamic>,
        chargesJson: results[4]! as Map<String, dynamic>,
        now: _clock(),
      ));
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  /// Parses the five reads. `tax_amount`/`tax_pct` are P4's columns on
  /// food_orders and activity_bookings; rows without them are untaxed.
  static InvoiceInput inputFrom({
    required Map<String, dynamic> reservationRow,
    required List<dynamic> foodRows,
    required List<dynamic> activityRows,
    required List<dynamic> paymentRows,
    required Map<String, dynamic> chargesJson,
    required DateTime now,
  }) {
    final property = reservationRow['properties'] as Map<String, dynamic>?;
    final unit = reservationRow['units'] as Map<String, dynamic>?;
    return InvoiceInput(
      reservation: Reservation.fromJson(reservationRow),
      resort: property == null
          ? null
          : InvoiceResort(
              name: property['name'] as String,
              slug: property['slug'] as String,
              address: property['address'] as String?,
              gstin: property['gstin'] as String?,
            ),
      unitName: unit?['name'] as String?,
      dayUse: reservationRow['slot_type_id'] != null,
      food: [
        for (final r in foodRows.cast<Map<String, dynamic>>()) _charge(r, 'total'),
      ],
      activities: [
        for (final r in activityRows.cast<Map<String, dynamic>>()) _charge(r, 'amount'),
      ],
      payments: [
        for (final p in paymentRows.cast<Map<String, dynamic>>()) _payment(p),
      ],
      charges: CurrentCharges.fromJson(chargesJson),
      now: now,
    );
  }

  static InvoiceCharge _charge(Map<String, dynamic> row, String amountKey) =>
      InvoiceCharge(
        amount: row[amountKey] as num,
        taxAmount: (row['tax_amount'] as num?) ?? 0,
        taxPct: row['tax_pct'] as num?,
      );

  static InvoicePayment _payment(Map<String, dynamic> row) {
    final method = PaymentMethod.fromWire(row['method'] as String?);
    // A desk payment's gateway_ref is the internal 'desk-<id>' retry guard;
    // what the guest recognises is the receipt/UTR typed into `reference`.
    final raw = (method == PaymentMethod.gateway
            ? row['gateway_ref']
            : row['reference']) as String?;
    final reference = raw?.trim();
    return InvoicePayment(
      kind: InvoicePaymentKind.fromWire(row['kind'] as String),
      amount: row['amount'] as num,
      method: method,
      reference: (reference == null || reference.isEmpty) ? null : reference,
      paidAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(ref.watch(supabaseProvider)),
);

/// The [InvoiceSource] seam every screen calls through.
final invoiceSourceProvider = Provider<InvoiceSource>(
  (ref) => ref.watch(invoiceRepositoryProvider),
);
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `flutter test test/data/invoice_repository_test.dart test/data/invoice_builder_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze
dart format lib/data/repositories/invoice_repository.dart test/data/invoice_repository_test.dart
git add lib/data/repositories/invoice_repository.dart test/data/invoice_repository_test.dart
git commit -m "feat(invoice): read invoices through existing RLS and current_charges

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
Expected analyze output: the 2 baseline infos only (the Task 1 `ignore: unused_field` is gone with the stub).

---

### Task 4: PDF renderers and the real exporter

**Files:**
- Create: `lib/core/pdf/report_pdf_renderer.dart`, `lib/core/pdf/invoice_pdf_renderer.dart`
- Modify: `lib/core/pdf/pdf_exporter.dart` (replace the stub)
- Test: `test/core/pdf/report_pdf_renderer_test.dart`, `test/core/pdf/invoice_pdf_renderer_test.dart`, `test/core/pdf/pdf_exporter_test.dart`

**Interfaces:**
- Consumes: `PdfFonts`, `loadPdfFonts`, `pdfMoney`, `pdfDate`, `ReportPdf`, `ReportPdfColumn`, `Invoice` (Task 1); `formatPct` (`lib/core/format.dart`); test support `testPdfFonts`, `sampleInvoice`.
- Produces: `pw.Document buildReportDocument(ReportPdf report, PdfFonts fonts, {bool compress = true, DateTime? generatedAt})`; `Future<Uint8List> renderReportPdf(ReportPdf report, PdfFonts fonts, {bool compress = true, DateTime? generatedAt})`; `pw.Document buildInvoiceDocument(Invoice invoice, PdfFonts fonts, {bool compress = true})`; `Future<Uint8List> renderInvoicePdf(Invoice invoice, PdfFonts fonts, {bool compress = true})`; `PasalaPdfExporter({Future<PdfFonts> Function()? loadFonts})`.

- [ ] **Step 1: Write the failing tests**

`test/core/pdf/report_pdf_renderer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/report_pdf.dart';
import 'package:pasala/core/pdf/report_pdf_renderer.dart';

import '../../support/pdf_test_fonts.dart';

ReportPdf _report(List<List<String>> rows, {List<String>? totals}) => ReportPdf(
      title: 'Settlements',
      resortName: 'Resort R',
      gstinLabel: 'GSTIN 29ABCDE1234F1Z5',
      periodLabel: '1 Aug 2026 – 31 Aug 2026',
      fileName: 'fin-r-settlements-2026-08-01-2026-08-31.pdf',
      columns: const [
        ReportPdfColumn('Guest', flex: 2),
        ReportPdfColumn('Total', numeric: true),
      ],
      rows: rows,
      totals: totals,
      notes: const ['Tax by category', 'Room: taxable ₹9,000.00, tax ₹1,080.00'],
    );

List<List<String>> _rows(int n) => [
      for (var i = 0; i < n; i++) ['Guest $i', '₹1,000.00'],
    ];

void main() {
  final fonts = testPdfFonts();

  test('a short report is a one-page PDF', () async {
    final doc = buildReportDocument(_report(_rows(3), totals: ['Total', '₹3,000.00']),
        fonts, generatedAt: DateTime(2026, 9, 25, 10));
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test('long reports run to many pages past the default 20-page limit', () async {
    final doc = buildReportDocument(_report(_rows(800)), fonts);
    await doc.save();
    expect(doc.document.pdfPageList.pages.length, greaterThan(20));
  });

  test('an empty report is one page with its message', () async {
    final doc = buildReportDocument(_report(const []), fonts);
    await doc.save();
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test('a row with the wrong number of cells is a programming error', () {
    expect(() => buildReportDocument(_report(const [['only one']]), fonts),
        throwsArgumentError);
    expect(
        () => buildReportDocument(_report(_rows(1), totals: const ['Total']), fonts),
        throwsArgumentError);
  });

  test('text the font cannot draw does not break the document', () async {
    final bytes = await renderReportPdf(
        _report(const [['सीता 🌸', '₹1.00']]), fonts);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
```

`test/core/pdf/invoice_pdf_renderer_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/invoice_pdf_renderer.dart';
import 'package:pasala/data/models/invoice.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/pdf_test_fonts.dart';

void main() {
  final fonts = testPdfFonts();

  test('the sample invoice is a one-page PDF', () async {
    final doc = buildInvoiceDocument(sampleInvoice(), fonts);
    final bytes = await doc.save();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(doc.document.pdfPageList.pages, hasLength(1));
  });

  test('a provisional bill with notes and no payments renders', () async {
    final bytes = await renderInvoicePdf(
      sampleInvoice(
        provisional: true,
        payments: const [],
        paid: 0,
        amountDue: 12660,
        notes: const ['The stay is still in progress, so this bill may change before checkout.'],
      ),
      fonts,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('many lines flow onto more pages', () async {
    final doc = buildInvoiceDocument(
      sampleInvoice(lines: [
        for (var i = 0; i < 80; i++)
          InvoiceLine(kind: InvoiceLineKind.foodDrink, label: 'Line $i', amount: 10),
      ]),
      fonts,
    );
    await doc.save();
    expect(doc.document.pdfPageList.pages.length, greaterThan(1));
  });

  test('a guest name in Devanagari still renders', () async {
    final bytes =
        await renderInvoicePdf(sampleInvoice(guestName: 'सीता 🌸'), fonts);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
```

`test/core/pdf/pdf_exporter_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/core/pdf/pdf_fonts.dart';
import 'package:pasala/core/pdf/report_pdf.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/pdf_test_fonts.dart';

const _report = ReportPdf(
  title: 'Collections',
  resortName: 'Resort R',
  gstinLabel: 'GSTIN not set',
  periodLabel: '1 Aug 2026 – 31 Aug 2026',
  fileName: 'fin-r-collections-2026-08-01-2026-08-31.pdf',
  columns: [ReportPdfColumn('Date'), ReportPdfColumn('Net', numeric: true)],
  rows: [['1 Aug 2026', '₹5,000.00']],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders invoices and reports, loading the fonts once', () async {
    var loads = 0;
    final exporter = PasalaPdfExporter(loadFonts: () async {
      loads++;
      return testPdfFonts();
    });
    final invoice = await exporter.invoice(sampleInvoice());
    final report = await exporter.report(_report);
    expect(String.fromCharCodes(invoice.take(5)), '%PDF-');
    expect(String.fromCharCodes(report.take(5)), '%PDF-');
    expect(loads, 1);
  });

  test('a failed font load is retried on the next export', () async {
    var loads = 0;
    final exporter = PasalaPdfExporter(loadFonts: () async {
      loads++;
      if (loads == 1) throw StateError('asset missing');
      return testPdfFonts();
    });
    await expectLater(exporter.report(_report), throwsStateError);
    final bytes = await exporter.report(_report);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(loads, 2);
  });

  test('the default exporter loads the bundled fonts', () async {
    final bytes = await PasalaPdfExporter().report(_report);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(await loadPdfFonts(), isA<PdfFonts>());
  });
}
```
If `doc.document.pdfPageList.pages` does not exist in the resolved `pdf` version, use `rip_grep_packages` for `class PdfPageList` / `pdfPageList` and use the equivalent page list; the assertion stays "number of pages".

- [ ] **Step 2: Run the tests to see them fail**

Run: `flutter test test/core/pdf`
Expected: FAIL — `report_pdf_renderer.dart`, `invoice_pdf_renderer.dart` not found; `PasalaPdfExporter` has no `loadFonts` parameter.

- [ ] **Step 3: Implement the report renderer**

`lib/core/pdf/report_pdf_renderer.dart`:
```dart
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';
import 'pdf_format.dart';
import 'report_pdf.dart';

/// A4 landscape, the resort/title/period on every page, the table header
/// repeated on every page, a bold totals row, notes, and "Page x of y".
/// `maxPages` is raised from pdf's default 20 so a year of settlements
/// still renders.
pw.Document buildReportDocument(
  ReportPdf report,
  PdfFonts fonts, {
  bool compress = true,
  DateTime? generatedAt,
}) {
  final width = report.columns.length;
  for (final row in [...report.rows, if (report.totals != null) report.totals!]) {
    if (row.length != width) {
      throw ArgumentError('Every row needs $width cells, got ${row.length}: $row');
    }
  }
  final s = fonts.safe;
  final at = (generatedAt ?? DateTime.now()).toLocal();
  const small = pw.TextStyle(fontSize: 8);
  const smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);

  pw.Widget cell(String text, ReportPdfColumn column, pw.TextStyle style) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          s(text),
          style: style,
          textAlign: column.numeric ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );

  pw.TableRow tableRow(List<String> cells, pw.TextStyle style,
          {bool repeat = false, PdfColor? shade}) =>
      pw.TableRow(
        repeat: repeat,
        decoration: shade == null ? null : pw.BoxDecoration(color: shade),
        children: [
          for (var i = 0; i < cells.length; i++) cell(cells[i], report.columns[i], style),
        ],
      );

  final doc = pw.Document(
    compress: compress,
    theme: fonts.theme,
    title: '${report.title} ${report.periodLabel}',
    creator: 'ResortHub',
  );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(28),
    maxPages: 1000,
    header: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          pw.Expanded(
            child: pw.Text(s(report.resortName),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(s(report.gstinLabel), style: const pw.TextStyle(fontSize: 9)),
        ]),
        pw.SizedBox(height: 2),
        pw.Text(s('${report.title} · ${report.periodLabel}'),
            style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 8),
      ],
    ),
    footer: (context) => pw.Row(children: [
      pw.Expanded(
        child: pw.Text('Generated ${pdfDate(at)} ${DateFormat.Hm().format(at)}',
            style: small),
      ),
      pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: small),
    ]),
    build: (context) => [
      if (report.rows.isEmpty)
        pw.Text(s(report.emptyMessage))
      else
        pw.Table(
          border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey500),
          columnWidths: {
            for (var i = 0; i < width; i++) i: pw.FlexColumnWidth(report.columns[i].flex),
          },
          children: [
            tableRow([for (final c in report.columns) c.header], smallBold,
                repeat: true, shade: PdfColors.grey200),
            for (final row in report.rows) tableRow(row, small),
            if (report.totals != null)
              tableRow(report.totals!, smallBold, shade: PdfColors.grey100),
          ],
        ),
      if (report.notes.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        for (final note in report.notes)
          pw.Text(s(note), style: const pw.TextStyle(fontSize: 9)),
      ],
    ],
  ));
  return doc;
}

Future<Uint8List> renderReportPdf(
  ReportPdf report,
  PdfFonts fonts, {
  bool compress = true,
  DateTime? generatedAt,
}) =>
    buildReportDocument(report, fonts, compress: compress, generatedAt: generatedAt)
        .save();
```

- [ ] **Step 4: Implement the invoice renderer**

`lib/core/pdf/invoice_pdf_renderer.dart`:
```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/invoice.dart';
import '../format.dart';
import 'pdf_fonts.dart';
import 'pdf_format.dart';

/// A4 portrait: the resort (name, address, GSTIN) and the title, number and
/// date; who and what was billed; the charge lines with Amount / Tax /
/// Total; totals; every payment; paid and amount due; notes.
pw.Document buildInvoiceDocument(
  Invoice invoice,
  PdfFonts fonts, {
  bool compress = true,
}) {
  final s = fonts.safe;
  const muted = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);
  const bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  String taxCell(InvoiceLine line) {
    if (line.tax == 0) return '—';
    final pct = line.taxPct;
    return pct == null
        ? pdfMoney(line.tax)
        : '${pdfMoney(line.tax)} (${formatPct(pct)}%)';
  }

  pw.Widget cell(String text, {bool right = false, pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(s(text),
            style: style,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  pw.Widget amountRow(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(s(label), style: strong ? bold : null)),
          pw.Text(s(value), style: strong ? bold : null),
        ]),
      );

  String paymentLabel(InvoicePayment p) => [
        p.kind.label,
        p.method.label,
        if (p.reference != null) 'Ref ${p.reference}',
        pdfDate(p.paidAt),
      ].join(' · ');

  final doc = pw.Document(
    compress: compress,
    theme: fonts.theme,
    title: '${invoice.title} ${invoice.number}',
    creator: 'ResortHub',
  );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    maxPages: 50,
    footer: (context) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
          style: muted),
    ),
    build: (context) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(s(invoice.resortName),
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              if (invoice.resortAddress != null)
                pw.Text(s(invoice.resortAddress!), style: muted),
              pw.Text(
                  s(invoice.gstin == null ? 'GSTIN not set' : 'GSTIN ${invoice.gstin}'),
                  style: muted),
            ],
          ),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(invoice.title.toUpperCase(),
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(s('No. ${invoice.number}')),
          pw.Text('Date ${pdfDate(invoice.issuedAt)}'),
        ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('BILLED TO', style: muted),
            pw.Text(s(invoice.guestName), style: bold),
          ]),
        ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('STAY', style: muted),
            if (invoice.unitName != null) pw.Text(s(invoice.unitName!), style: bold),
            pw.Text('${pdfDate(invoice.stayStart)} – ${pdfDate(invoice.stayEnd)}'),
            if (invoice.guests != null) pw.Text('${invoice.guests} guests'),
          ]),
        ),
      ]),
      pw.SizedBox(height: 18),
      pw.Table(
        border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey400),
        columnWidths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(1.4),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              cell('Description', style: bold),
              cell('Amount', right: true, style: bold),
              cell('Tax', right: true, style: bold),
              cell('Total', right: true, style: bold),
            ],
          ),
          for (final line in invoice.lines)
            pw.TableRow(children: [
              cell(line.label),
              cell(pdfMoney(line.amount), right: true),
              cell(taxCell(line), right: true),
              cell(pdfMoney(line.total), right: true),
            ]),
        ],
      ),
      pw.SizedBox(height: 10),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.SizedBox(
          width: 240,
          child: pw.Column(children: [
            amountRow('Subtotal (excl. tax)', pdfMoney(invoice.subtotal)),
            amountRow('Tax', pdfMoney(invoice.taxTotal)),
            amountRow('Total', pdfMoney(invoice.total), strong: true),
          ]),
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Text('PAYMENTS', style: muted),
      if (invoice.payments.isEmpty) pw.Text('No payments yet.'),
      for (final p in invoice.payments) amountRow(paymentLabel(p), pdfMoney(p.amount)),
      pw.Divider(color: PdfColors.grey400, thickness: 0.5),
      amountRow('Total paid', pdfMoney(invoice.paid)),
      amountRow('Amount due', pdfMoney(invoice.amountDue), strong: true),
      pw.SizedBox(height: 18),
      for (final note in invoice.notes) pw.Text(s(note), style: muted),
      pw.Text('This is a computer-generated document; no signature is required.',
          style: muted),
    ],
  ));
  return doc;
}

Future<Uint8List> renderInvoicePdf(
  Invoice invoice,
  PdfFonts fonts, {
  bool compress = true,
}) =>
    buildInvoiceDocument(invoice, fonts, compress: compress).save();
```

- [ ] **Step 5: Replace the exporter stub**

`lib/core/pdf/pdf_exporter.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/invoice.dart';
import 'invoice_pdf_renderer.dart';
import 'pdf_fonts.dart';
import 'report_pdf.dart';
import 'report_pdf_renderer.dart';

/// Turns an [Invoice] or a [ReportPdf] into PDF bytes. Tests override
/// [pdfExporterProvider] with `FakePdfExporter`.
abstract class PdfExporter {
  Future<Uint8List> invoice(Invoice invoice);
  Future<Uint8List> report(ReportPdf report);
}

/// Loads the bundled fonts on first use (and again after a failed load),
/// then renders with them.
class PasalaPdfExporter implements PdfExporter {
  PasalaPdfExporter({Future<PdfFonts> Function()? loadFonts})
      : _loadFonts = loadFonts ?? loadPdfFonts;

  final Future<PdfFonts> Function() _loadFonts;
  Future<PdfFonts>? _fonts;

  Future<PdfFonts> _fontsOnce() async {
    final pending = _fonts ??= _loadFonts();
    try {
      return await pending;
    } catch (_) {
      if (identical(_fonts, pending)) _fonts = null;
      rethrow;
    }
  }

  @override
  Future<Uint8List> invoice(Invoice invoice) async =>
      renderInvoicePdf(invoice, await _fontsOnce());

  @override
  Future<Uint8List> report(ReportPdf report) async =>
      renderReportPdf(report, await _fontsOnce());
}

final pdfExporterProvider = Provider<PdfExporter>((ref) => PasalaPdfExporter());
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `flutter test test/core/pdf`
Expected: PASS (all renderer, exporter, font and format tests). The 800-row test takes a few seconds.

- [ ] **Step 7: Analyze, format, commit**

```bash
flutter analyze
dart format lib/core/pdf/report_pdf_renderer.dart lib/core/pdf/invoice_pdf_renderer.dart lib/core/pdf/pdf_exporter.dart test/core/pdf/report_pdf_renderer_test.dart test/core/pdf/invoice_pdf_renderer_test.dart test/core/pdf/pdf_exporter_test.dart
git add lib/core/pdf test/core/pdf
git commit -m "feat(pdf): render invoices and tabular reports with the bundled fonts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Invoice download in the app

**Files:**
- Create: `lib/features/invoice/invoice_pdf_button.dart`
- Modify: `lib/features/account/booking_detail_screen.dart` (after the `_QuoteBreakdown` card in `_DetailState.build`)
- Modify: `lib/features/stay/final_invoice_screen.dart` (class doc comment; the `ListView` children before "Leave a review")
- Modify: `lib/features/finance/finance_settlements_tab.dart` (`_SettlementCard.build`, `_SettlementsTable.build`)
- Test: `test/features/invoice/invoice_pdf_button_test.dart`, `test/features/account/booking_detail_invoice_test.dart`, `test/features/stay/final_invoice_screen_test.dart`, `test/features/finance/finance_settlements_invoice_test.dart`

**Interfaces:**
- Consumes: `invoiceSourceProvider`, `pdfExporterProvider`, `pdfDelivererProvider`, `Invoice.fileName/number` (Task 1); `FailureView.messageFor`, `BookingFailure`; test fakes `FakeInvoiceSource`, `FakePdfExporter`, `PdfDeliveries`, `sampleInvoice`; `FakeFinanceSource`, `settlementRow` (`test/support/fake_finance_source.dart`).
- Produces: `Future<void> downloadInvoicePdf(BuildContext context, WidgetRef ref, String reservationId)` (P5 calls this from reception's post-checkout action); `enum InvoicePdfButtonStyle { button, icon }`; `InvoicePdfButton({Key? key, required String reservationId, InvoicePdfButtonStyle style = InvoicePdfButtonStyle.button})` — button style key `Key('invoice-pdf-button')`, icon style key `Key('invoice-pdf-<reservationId>')`, tooltip "Invoice PDF".

- [ ] **Step 1: Write the failing button tests**

`test/features/invoice/invoice_pdf_button_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/invoice/invoice_pdf_button.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

Future<void> _pump(
  WidgetTester tester, {
  required FakeInvoiceSource source,
  required FakePdfExporter exporter,
  required PdfDeliveries deliveries,
  InvoicePdfButtonStyle style = InvoicePdfButtonStyle.button,
}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        invoiceSourceProvider.overrideWithValue(source),
        pdfExporterProvider.overrideWithValue(exporter),
        pdfDelivererProvider.overrideWithValue(deliveries.deliver),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: InvoicePdfButton(reservationId: 'r1', style: style)),
        ),
      ),
    ));

void main() {
  testWidgets('builds, renders and delivers the invoice', (tester) async {
    final source = FakeInvoiceSource();
    final exporter = FakePdfExporter();
    final deliveries = PdfDeliveries();
    await _pump(tester, source: source, exporter: exporter, deliveries: deliveries);

    await tester.tap(find.text('Download invoice (PDF)'));
    await tester.pumpAndSettle();

    expect(source.calls, ['r1']);
    expect(exporter.invoices.single.number, 'FIN-R-3F2A9C1B');
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
    expect(deliveries.files.single.$2, FakePdfExporter.bytes);
    expect(find.text('Invoice FIN-R-3F2A9C1B is ready.'), findsOneWidget);
  });

  testWidgets('shows the refusal from the invoice builder', (tester) async {
    final source = FakeInvoiceSource()
      ..error = const InvalidState('An invoice is available once the guest has checked in.');
    final exporter = FakePdfExporter();
    await _pump(tester, source: source, exporter: exporter, deliveries: PdfDeliveries());

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(find.text('An invoice is available once the guest has checked in.'),
        findsOneWidget);
    expect(exporter.invoices, isEmpty);
  });

  testWidgets('says so when the device cannot take the file', (tester) async {
    await _pump(tester,
        source: FakeInvoiceSource(),
        exporter: FakePdfExporter(),
        deliveries: PdfDeliveries(delivers: false));

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(find.text("Invoice download isn't available on this device yet."),
        findsOneWidget);
  });

  testWidgets('a renderer failure reads as a retryable error', (tester) async {
    final deliveries = PdfDeliveries();
    await _pump(tester,
        source: FakeInvoiceSource(),
        exporter: FakePdfExporter()..error = StateError('font'),
        deliveries: deliveries);

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't create the invoice PDF. Try again."), findsOneWidget);
    expect(deliveries.files, isEmpty);
  });

  testWidgets('a second tap while working does nothing', (tester) async {
    final hold = Completer<void>();
    final source = FakeInvoiceSource()..hold = hold;
    final deliveries = PdfDeliveries();
    await _pump(tester, source: source, exporter: FakePdfExporter(), deliveries: deliveries);

    await tester.tap(find.byKey(const Key('invoice-pdf-button')));
    await tester.pump();
    expect(find.text('Preparing invoice…'), findsOneWidget);
    await tester.tap(find.byKey(const Key('invoice-pdf-button')), warnIfMissed: false);
    await tester.pump();
    expect(source.calls, ['r1']);

    hold.complete();
    await tester.pumpAndSettle();
    expect(deliveries.files, hasLength(1));
    expect(find.text('Download invoice (PDF)'), findsOneWidget);
  });

  testWidgets('the icon style is an "Invoice PDF" button', (tester) async {
    final deliveries = PdfDeliveries();
    await _pump(tester,
        source: FakeInvoiceSource(),
        exporter: FakePdfExporter(),
        deliveries: deliveries,
        style: InvoicePdfButtonStyle.icon);

    expect(find.byKey(const Key('invoice-pdf-r1')), findsOneWidget);
    await tester.tap(find.byTooltip('Invoice PDF'));
    await tester.pumpAndSettle();
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
  });
}
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/features/invoice/invoice_pdf_button_test.dart`
Expected: FAIL — `invoice_pdf_button.dart` not found.

- [ ] **Step 3: Implement the button**

`lib/features/invoice/invoice_pdf_button.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/pdf/pdf_delivery.dart';
import '../../core/pdf/pdf_exporter.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/invoice_repository.dart';

/// Reads, renders and delivers the invoice of [reservationId], reporting
/// the outcome in a SnackBar. Everything it needs is read before the first
/// await, so it still finishes and reports if the calling widget is gone by
/// then (P5 calls it from reception's post-checkout SnackBar action).
Future<void> downloadInvoicePdf(
  BuildContext context,
  WidgetRef ref,
  String reservationId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final source = ref.read(invoiceSourceProvider);
  final exporter = ref.read(pdfExporterProvider);
  final deliver = ref.read(pdfDelivererProvider);
  void show(String message) => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  try {
    final invoice = await source.invoice(reservationId);
    final bytes = await exporter.invoice(invoice);
    final delivered = await deliver(invoice.fileName, bytes);
    show(delivered
        ? 'Invoice ${invoice.number} is ready.'
        : "Invoice download isn't available on this device yet.");
  } on BookingFailure catch (e) {
    show(FailureView.messageFor(e));
  } catch (_) {
    show("Couldn't create the invoice PDF. Try again.");
  }
}

enum InvoicePdfButtonStyle { button, icon }

/// "Download invoice (PDF)" (full width in a card) or a compact "Invoice
/// PDF" icon for list rows. Disabled, with a spinner, while working.
class InvoicePdfButton extends ConsumerStatefulWidget {
  const InvoicePdfButton({
    super.key,
    required this.reservationId,
    this.style = InvoicePdfButtonStyle.button,
  });

  final String reservationId;
  final InvoicePdfButtonStyle style;

  @override
  ConsumerState<InvoicePdfButton> createState() => _InvoicePdfButtonState();
}

class _InvoicePdfButtonState extends ConsumerState<InvoicePdfButton> {
  bool _busy = false;

  static const _spinner = SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await downloadInvoicePdf(context, ref, widget.reservationId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => switch (widget.style) {
        InvoicePdfButtonStyle.icon => IconButton(
            key: Key('invoice-pdf-${widget.reservationId}'),
            tooltip: 'Invoice PDF',
            onPressed: _busy ? null : _download,
            icon: _busy ? _spinner : const Icon(Icons.picture_as_pdf_outlined),
          ),
        InvoicePdfButtonStyle.button => OutlinedButton.icon(
            key: const Key('invoice-pdf-button'),
            onPressed: _busy ? null : _download,
            icon: _busy ? _spinner : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_busy ? 'Preparing invoice…' : 'Download invoice (PDF)'),
          ),
      };
}
```

Run: `flutter test test/features/invoice/invoice_pdf_button_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 4: Write the failing screen tests**

`test/features/account/booking_detail_invoice_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/quote.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/account/booking_detail_screen.dart';
import 'package:pasala/features/booking/providers.dart' show reservationProvider;

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

Reservation _reservation(ReservationStatus status,
        {ReservationKind kind = ReservationKind.booking}) =>
    Reservation(
      id: 'r1',
      unitId: 'u1',
      start: DateTime.utc(2026, 8, 10, 8, 30),
      end: DateTime.utc(2026, 8, 12, 5, 30),
      kind: kind,
      status: status,
      guests: 2,
      quote: kind == ReservationKind.booking
          ? Quote(
              currency: 'INR',
              guests: 2,
              lines: [
                QuoteLine(
                    date: DateTime.utc(2026, 8, 10),
                    label: 'Weekday rate',
                    amount: 5000,
                    extraGuests: 0,
                    extraGuestAmount: 0),
              ],
              subtotal: 5000,
              cleaningFee: 0,
              total: 5000,
            )
          : null,
    );

Future<(FakeInvoiceSource, PdfDeliveries)> _open(
    WidgetTester tester, Reservation reservation) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = FakeInvoiceSource();
  final deliveries = PdfDeliveries();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      reservationProvider(reservation.id).overrideWith((ref) async => reservation),
      invoiceSourceProvider.overrideWithValue(source),
      pdfExporterProvider.overrideWithValue(FakePdfExporter()),
      pdfDelivererProvider.overrideWithValue(deliveries.deliver),
    ],
    child: MaterialApp(home: BookingDetailScreen(reservationId: reservation.id)),
  ));
  await tester.pumpAndSettle();
  return (source, deliveries);
}

void main() {
  for (final status in [ReservationStatus.checkedIn, ReservationStatus.checkedOut]) {
    testWidgets('a ${status.name} booking offers its invoice', (tester) async {
      final (source, deliveries) = await _open(tester, _reservation(status));

      await tester.tap(find.byKey(const Key('invoice-pdf-button')));
      await tester.pumpAndSettle();

      expect(source.calls, ['r1']);
      expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
    });
  }

  for (final status in [
    ReservationStatus.hold,
    ReservationStatus.pendingPayment,
    ReservationStatus.confirmed,
    ReservationStatus.cancelled,
  ]) {
    testWidgets('a ${status.name} booking has no invoice yet', (tester) async {
      await _open(tester, _reservation(status));
      expect(find.byKey(const Key('invoice-pdf-button')), findsNothing);
    });
  }

  testWidgets('an OTA row never offers an invoice', (tester) async {
    await _open(tester,
        _reservation(ReservationStatus.checkedIn, kind: ReservationKind.ota));
    expect(find.byKey(const Key('invoice-pdf-button')), findsNothing);
  });
}
```

`test/features/stay/final_invoice_screen_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/current_charges.dart';
import 'package:pasala/data/models/reservation.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/data/repositories/stay_repository.dart';
import 'package:pasala/features/booking/providers.dart' show reservationProvider;
import 'package:pasala/features/stay/final_invoice_screen.dart';

import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

// A full uuid: the screen shows `id.substring(0, 8)`.
const _id = '3f2a9c1b-0000-4000-8000-000000000001';

void main() {
  testWidgets('offers the PDF above "Leave a review"', (tester) async {
    final source = FakeInvoiceSource();
    final deliveries = PdfDeliveries();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        reservationProvider(_id).overrideWith((ref) async => Reservation(
              id: _id,
              unitId: 'u1',
              start: DateTime.utc(2026, 8, 10, 8, 30),
              end: DateTime.utc(2026, 8, 12, 5, 30),
              kind: ReservationKind.booking,
              status: ReservationStatus.checkedOut,
            )),
        currentChargesProvider(_id).overrideWith((ref) async => const CurrentCharges(
              stayAmount: 10640,
              foodAmount: 840,
              activityAmount: 1180,
              total: 12660,
              paid: 12660,
              balance: 0,
            )),
        invoiceSourceProvider.overrideWithValue(source),
        pdfExporterProvider.overrideWithValue(FakePdfExporter()),
        pdfDelivererProvider.overrideWithValue(deliveries.deliver),
      ],
      child: const MaterialApp(home: FinalInvoiceScreen(reservationId: _id)),
    ));
    await tester.pumpAndSettle();

    final pdf = find.byKey(const Key('invoice-pdf-button'));
    expect(pdf, findsOneWidget);
    expect(tester.getTopLeft(pdf).dy,
        lessThan(tester.getTopLeft(find.text('Leave a review')).dy));

    await tester.tap(pdf);
    await tester.pumpAndSettle();
    expect(source.calls, [_id]);
    expect(deliveries.files.single.$1, 'invoice-FIN-R-3F2A9C1B.pdf');
  });
}
```

`test/features/finance/finance_settlements_invoice_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/data/repositories/invoice_repository.dart';
import 'package:pasala/features/finance/finance_settlements_tab.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_invoice_source.dart';
import '../../support/fake_pdf_exporter.dart';

final _filter =
    (from: DateTime(2026, 8, 1), to: DateTime(2026, 8, 31), propertyId: 'p1');

Future<FakeInvoiceSource> _pump(WidgetTester tester, {required bool wide}) async {
  tester.view.physicalSize = wide ? const Size(1400, 1200) : const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = FakeInvoiceSource();
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      financeSourceProvider.overrideWithValue(FakeFinanceSource()
        ..settlementRows = [
          settlementRow(reservationId: 'r1', room: 5000),
          settlementRow(reservationId: 'r2', guestName: 'Ravi Rao', room: 7000),
        ]),
      invoiceSourceProvider.overrideWithValue(source),
      pdfExporterProvider.overrideWithValue(FakePdfExporter()),
      pdfDelivererProvider.overrideWithValue(PdfDeliveries().deliver),
    ],
    child: MaterialApp(home: Scaffold(body: FinanceSettlementsTab(filter: _filter))),
  ));
  await tester.pumpAndSettle();
  return source;
}

void main() {
  testWidgets('each settlement card has its own invoice PDF', (tester) async {
    final source = await _pump(tester, wide: false);

    expect(find.byTooltip('Invoice PDF'), findsNWidgets(2));
    expect(find.text('Settled'), findsNWidgets(2));
    await tester.tap(find.descendant(
        of: find.byKey(const Key('settlement-r2')),
        matching: find.byTooltip('Invoice PDF')));
    await tester.pumpAndSettle();

    expect(source.calls, ['r2']);
  });

  testWidgets('the wide table has an Invoice column', (tester) async {
    final source = await _pump(tester, wide: true);

    expect(find.text('Invoice'), findsOneWidget);
    // The table scrolls sideways; bring its last column into view first.
    await tester.ensureVisible(find.byKey(const Key('invoice-pdf-r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('invoice-pdf-r1')));
    await tester.pumpAndSettle();

    expect(source.calls, ['r1']);
  });
}
```
(1400 px is above the 840 breakpoint, so the tab shows its `DataTable`.)

- [ ] **Step 5: Run to see them fail**

Run: `flutter test test/features/account/booking_detail_invoice_test.dart test/features/stay/final_invoice_screen_test.dart test/features/finance/finance_settlements_invoice_test.dart`
Expected: FAIL — no `invoice-pdf-button` / `Invoice PDF` on those screens.

- [ ] **Step 6: Wire the button into the three screens**

`lib/features/account/booking_detail_screen.dart` — add the import:
```dart
import '../invoice/invoice_pdf_button.dart';
```
and, in `_DetailState.build`, directly after the block
```dart
        if (quote != null) ...[
          const SizedBox(height: Spacing.lg),
          _DetailCard(child: _QuoteBreakdown(quote: quote)),
        ],
```
insert:
```dart
        // A guest booking's invoice, once the guest has checked in: the
        // guest's own copy, and the one owners/admins reach from
        // /admin/bookings. buildInvoice refuses every other state anyway.
        if (reservation.kind == ReservationKind.booking &&
            (reservation.status == ReservationStatus.checkedIn ||
                reservation.status == ReservationStatus.checkedOut)) ...[
          const SizedBox(height: Spacing.lg),
          _DetailCard(
            child: SizedBox(
              width: double.infinity,
              child: InvoicePdfButton(reservationId: reservation.id),
            ),
          ),
        ],
```

`lib/features/stay/final_invoice_screen.dart` — add the import:
```dart
import '../invoice/invoice_pdf_button.dart';
```
replace the class doc comment
```dart
/// Itemized final invoice -- no PDF export, matching this repo's already
/// -deferred decision not to build PDF export for reports either.
```
with
```dart
/// Itemized final invoice, with its PDF (`InvoicePdfButton`). The guest
/// lands here after self-checkout, and reception after a desk checkout.
```
and replace
```dart
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: () =>
                    context.push('/my-stay/review/$reservationId'),
                child: const Text('Leave a review'),
              ),
```
with
```dart
              const SizedBox(height: Spacing.lg),
              InvoicePdfButton(reservationId: reservationId),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                onPressed: () =>
                    context.push('/my-stay/review/$reservationId'),
                child: const Text('Leave a review'),
              ),
```

`lib/features/finance/finance_settlements_tab.dart` — add the import:
```dart
import '../invoice/invoice_pdf_button.dart';
```
In `_SettlementCard.build`, replace
```dart
            if (r.outstanding != 0) _OutstandingFlag(row: r) else const Text('Settled'),
```
with
```dart
            Row(children: [
              Expanded(
                child: r.outstanding != 0
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: _OutstandingFlag(row: r),
                      )
                    : const Text('Settled'),
              ),
              InvoicePdfButton(
                reservationId: r.reservationId,
                style: InvoicePdfButtonStyle.icon,
              ),
            ]),
```
In `_SettlementsTable.build`, append to the `columns` list (after `DataColumn(label: Text('Outstanding'))`):
```dart
            DataColumn(label: Text('Invoice')),
```
and append to each `DataRow`'s `cells` (after the Outstanding cell):
```dart
                DataCell(InvoicePdfButton(
                  reservationId: r.reservationId,
                  style: InvoicePdfButtonStyle.icon,
                )),
```

- [ ] **Step 7: Run the new and the neighbouring tests**

Run:
```bash
flutter test test/features/invoice test/features/account test/features/stay test/features/finance
```
Expected: PASS, including the existing `booking_detail_screen_test.dart`, `checkout_screen_test.dart` and `finance_screen_test.dart`.

- [ ] **Step 8: Analyze, format the new files, commit**

```bash
flutter analyze
dart format lib/features/invoice/invoice_pdf_button.dart test/features/invoice/invoice_pdf_button_test.dart test/features/account/booking_detail_invoice_test.dart test/features/stay/final_invoice_screen_test.dart test/features/finance/finance_settlements_invoice_test.dart
git add lib/features/invoice test/features/invoice lib/features/account/booking_detail_screen.dart lib/features/stay/final_invoice_screen.dart lib/features/finance/finance_settlements_tab.dart test/features/account/booking_detail_invoice_test.dart test/features/stay/final_invoice_screen_test.dart test/features/finance/finance_settlements_invoice_test.dart
git commit -m "feat(invoice): download the booking invoice PDF from booking detail, final invoice and settlements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
(Do not `dart format` the three pre-existing screens; keep your inserted code in their existing style by hand.)

---

### Task 6: Finance report PDF builders

**Files:**
- Create: `lib/features/finance/finance_pdf.dart`
- Test: `test/features/finance/finance_pdf_test.dart`

**Interfaces:**
- Consumes: `ReportPdf`, `ReportPdfColumn` (Task 1); `FinanceResort`, `CollectionRow`, `LedgerRow`, `LedgerCategory`, `SettlementRow` (`lib/data/models/finance.dart`); `collectionsByDay`, `collectionsTotal`, `CollectionDay`, `formatMoney`, `isoDate` (`lib/features/finance/finance_tables.dart`); `gstinLabel` (`lib/features/finance/finance_csv.dart`); `formatDate`, `formatPct` (`lib/core/format.dart`); `PaymentMethod`.
- Produces: `String financePdfFileName(String slug, String report, DateTime from, DateTime to)`; `ReportPdf collectionsPdf(FinanceResort resort, DateTime from, DateTime to, List<CollectionRow> rows)`; `ReportPdf ledgerPdf(FinanceResort resort, DateTime from, DateTime to, List<LedgerRow> rows)`; `ReportPdf settlementsPdf(FinanceResort resort, DateTime from, DateTime to, List<SettlementRow> rows)`.

- [ ] **Step 1: Write the failing tests**

`test/features/finance/finance_pdf_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/finance.dart';
import 'package:pasala/data/models/payment_method.dart';
import 'package:pasala/features/finance/finance_pdf.dart';
import 'package:pasala/features/finance/finance_tables.dart';

import '../../support/fake_finance_source.dart';

final _from = DateTime(2026, 8, 1);
final _to = DateTime(2026, 8, 31);
String m(num v) => formatMoney(v);

void main() {
  final resort = financeResort();

  test('file names follow the CSV names with .pdf', () {
    expect(financePdfFileName('fin-r', 'ledger', _from, _to),
        'fin-r-ledger-2026-08-01-2026-08-31.pdf');
  });

  group('Collections', () {
    final rows = [
      collectionRow(day: DateTime(2026, 8, 1), amount: 5000),
      collectionRow(day: DateTime(2026, 8, 5), source: CollectionSource.refund, amount: -1500),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.cash,
          amount: 550),
      collectionRow(
          day: DateTime(2026, 8, 10),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.walkInSale,
          method: PaymentMethod.upi,
          amount: 300),
      collectionRow(
          day: DateTime(2026, 8, 12),
          channel: CollectionChannel.frontDesk,
          source: CollectionSource.checkoutBalance,
          method: PaymentMethod.cash,
          amount: 7540),
    ];

    test('one row per day, online and each desk method, refunds and net', () {
      final pdf = collectionsPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Collections');
      expect(pdf.resortName, 'Resort R');
      expect(pdf.gstinLabel, 'GSTIN 29ABCDE1234F1Z5');
      expect(pdf.periodLabel, '1 Aug 2026 – 31 Aug 2026');
      expect(pdf.fileName, 'fin-r-collections-2026-08-01-2026-08-31.pdf');
      expect(pdf.columns.map((c) => c.header),
          ['Date', 'Online', 'Cash', 'Card', 'UPI', 'Bank', 'Other', 'Refunds', 'Net']);
      expect(pdf.rows, [
        ['1 Aug 2026', m(5000), m(0), m(0), m(0), m(0), m(0), m(0), m(5000)],
        ['5 Aug 2026', m(0), m(0), m(0), m(0), m(0), m(0), m(-1500), m(-1500)],
        ['10 Aug 2026', m(0), m(550), m(0), m(300), m(0), m(0), m(0), m(850)],
        ['12 Aug 2026', m(0), m(7540), m(0), m(0), m(0), m(0), m(0), m(7540)],
      ]);
      expect(pdf.totals,
          ['Total', m(5000), m(8090), m(0), m(300), m(0), m(0), m(-1500), m(11890)]);
    });

    test('an empty period has no totals and says so', () {
      final pdf = collectionsPdf(resort, _from, _to, const []);
      expect(pdf.rows, isEmpty);
      expect(pdf.totals, isNull);
      expect(pdf.emptyMessage, 'No collections in this period.');
    });
  });

  group('Ledger', () {
    final rows = [
      ledgerRow(day: DateTime(2026, 8, 10), gross: 10000, discount: 1000, tax: 1080),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.ancillary,
          source: 'cleaning_fee',
          gross: 500,
          tax: 60),
      ledgerRow(
          day: DateTime(2026, 8, 10),
          category: LedgerCategory.ancillary,
          source: 'cancellation_fee',
          gross: 2000),
      ledgerRow(
          day: DateTime(2026, 8, 11),
          category: LedgerCategory.foodBeverage,
          source: 'in_stay_order',
          gross: 840,
          tax: 40),
      ledgerRow(
          day: DateTime(2026, 8, 11),
          category: LedgerCategory.spaActivities,
          source: 'activity_booking',
          gross: 1180,
          tax: 180),
    ];

    test('one row per day and category, sources summed, in category order', () {
      final pdf = ledgerPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Ledger');
      expect(pdf.columns.map((c) => c.header),
          ['Date', 'Category', 'Gross', 'Discount', 'Taxable', 'Tax', 'Net']);
      expect(pdf.rows, [
        ['10 Aug 2026', 'Room', m(10000), m(1000), m(9000), m(1080), m(10080)],
        ['10 Aug 2026', 'Ancillary', m(2500), m(0), m(2500), m(60), m(2560)],
        ['11 Aug 2026', 'F&B', m(840), m(0), m(840), m(40), m(880)],
        ['11 Aug 2026', 'Spa/Activities', m(1180), m(0), m(1180), m(180), m(1360)],
      ]);
      expect(pdf.totals,
          ['Total', '', m(14520), m(1000), m(13520), m(1360), m(14880)]);
    });

    test('notes give taxable and tax per category over the period', () {
      expect(ledgerPdf(resort, _from, _to, rows).notes, [
        'Tax by category',
        'Room: taxable ${m(9000)}, tax ${m(1080)}',
        'F&B: taxable ${m(840)}, tax ${m(40)}',
        'Spa/Activities: taxable ${m(1180)}, tax ${m(180)}',
        'Ancillary: taxable ${m(2500)}, tax ${m(60)}',
      ]);
    });

    test('an empty period says so', () {
      final pdf = ledgerPdf(resort, _from, _to, const []);
      expect(pdf.totals, isNull);
      expect(pdf.notes, isEmpty);
      expect(pdf.emptyMessage, 'No revenue in this period.');
    });
  });

  group('Settlements', () {
    final rows = [
      settlementRow(
        reservationId: 'r1',
        room: 9000,
        cleaningFee: 500,
        taxPct: 12,
        tax: 1140,
        food: 840,
        activities: 1180,
        advancePaid: 3192,
        balanceDesk: 9468,
        deskMethod: PaymentMethod.cash,
        deskReference: 'R-17',
      ),
      settlementRow(
        reservationId: 'r2',
        guestName: 'Ravi Rao',
        unitName: 'Lake Villa',
        room: 5000,
        advancePaid: 2000,
        balanceOnline: 3000,
      ),
      settlementRow(
        reservationId: 'r3',
        guestName: 'Owes Money',
        room: 1000,
        outstanding: 1000,
      ),
    ];

    test('one condensed row per checkout, and a totals row', () {
      final pdf = settlementsPdf(resort, _from, _to, rows);
      expect(pdf.title, 'Settlements');
      expect(pdf.columns.map((c) => c.header), [
        'Guest', 'Unit', 'Stay', 'Room', 'Cleaning', 'Tax', 'Food', 'Activities',
        'Total', 'Advance', 'Balance', 'Paid by', 'Outstanding',
      ]);
      expect(pdf.rows, [
        ['Gita Guest', 'Cottage 1', '10 Aug 2026 – 12 Aug 2026', m(9000), m(500),
          '${m(1140)} (12%)', m(840), m(1180), m(12660), m(3192), m(9468),
          'Cash · R-17', m(0)],
        ['Ravi Rao', 'Lake Villa', '10 Aug 2026 – 12 Aug 2026', m(5000), m(0),
          m(0), m(0), m(0), m(5000), m(2000), m(3000), 'Online', m(0)],
        ['Owes Money', 'Cottage 1', '10 Aug 2026 – 12 Aug 2026', m(1000), m(0),
          m(0), m(0), m(0), m(1000), m(0), m(0), '—', m(1000)],
      ]);
      expect(pdf.totals, ['Total', '', '', m(15000), m(500), m(1140), m(840),
        m(1180), m(18660), m(5192), m(12468), '', m(1000)]);
    });

    test('an empty period says so', () {
      final pdf = settlementsPdf(resort, _from, _to, const []);
      expect(pdf.totals, isNull);
      expect(pdf.emptyMessage, 'No checkouts in this period.');
    });

    test('every row fits the columns', () {
      final pdf = settlementsPdf(resort, _from, _to, rows);
      for (final row in [...pdf.rows, pdf.totals!]) {
        expect(row, hasLength(pdf.columns.length));
      }
    });
  });

  test('a resort without GSTIN says so', () {
    expect(collectionsPdf(financeResort(gstin: null), _from, _to, const []).gstinLabel,
        'GSTIN not set');
  });
}
```

- [ ] **Step 2: Run to see it fail**

Run: `flutter test test/features/finance/finance_pdf_test.dart`
Expected: FAIL — `finance_pdf.dart` not found.

- [ ] **Step 3: Implement the builders**

`lib/features/finance/finance_pdf.dart`:
```dart
import '../../core/format.dart';
import '../../core/pdf/report_pdf.dart';
import '../../data/models/finance.dart';
import '../../data/models/payment_method.dart';
import 'finance_csv.dart' show gstinLabel;
import 'finance_tables.dart';

/// `<slug>-<report>-<from>-<to>.pdf`: the CSV's name with `.pdf`.
String financePdfFileName(String slug, String report, DateTime from, DateTime to) =>
    '$slug-$report-${isoDate(from)}-${isoDate(to)}.pdf';

String _period(DateTime from, DateTime to) =>
    '${formatDate(from)} – ${formatDate(to)}';

num _sum(Iterable<num> values) => values.fold<num>(0, (a, b) => a + b);

/// Collections as on screen: one row per day, online and each desk method,
/// refunds (negative) and the day's net; a totals row.
ReportPdf collectionsPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<CollectionRow> rows,
) {
  final days = collectionsByDay(rows);
  List<String> cells(CollectionDay d) => [
        d.day == null ? 'Total' : formatDate(d.day!),
        formatMoney(d.online),
        for (final m in PaymentMethod.desk) formatMoney(d.deskFor(m)),
        formatMoney(d.refunds),
        formatMoney(d.net),
      ];
  return ReportPdf(
    title: 'Collections',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'collections', from, to),
    columns: [
      const ReportPdfColumn('Date', flex: 1.4),
      const ReportPdfColumn('Online', numeric: true),
      for (final m in PaymentMethod.desk)
        ReportPdfColumn(m == PaymentMethod.bankTransfer ? 'Bank' : m.label, numeric: true),
      const ReportPdfColumn('Refunds', numeric: true),
      const ReportPdfColumn('Net', numeric: true),
    ],
    rows: [for (final d in days) cells(d)],
    totals: days.isEmpty ? null : cells(collectionsTotal(days)),
    emptyMessage: 'No collections in this period.',
  );
}

/// Running sums of ledger lines.
class _LedgerSum {
  num gross = 0, discount = 0, taxable = 0, tax = 0, net = 0;

  void add(LedgerRow r) {
    gross += r.gross;
    discount += r.discount;
    taxable += r.taxable;
    tax += r.tax;
    net += r.net;
  }

  List<String> get money => [
        formatMoney(gross),
        formatMoney(discount),
        formatMoney(taxable),
        formatMoney(tax),
        formatMoney(net),
      ];
}

/// Ledger with tax per category: one row per day and category (the
/// sources of a category summed), a totals row, and a "Tax by category"
/// note block over the whole period.
ReportPdf ledgerPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<LedgerRow> rows,
) {
  final byDayCategory = <(DateTime, LedgerCategory), _LedgerSum>{};
  final byCategory = <LedgerCategory, _LedgerSum>{};
  final total = _LedgerSum();
  for (final r in rows) {
    byDayCategory.putIfAbsent((r.day, r.category), _LedgerSum.new).add(r);
    byCategory.putIfAbsent(r.category, _LedgerSum.new).add(r);
    total.add(r);
  }
  final keys = byDayCategory.keys.toList()
    ..sort((a, b) {
      final byDay = a.$1.compareTo(b.$1);
      return byDay != 0 ? byDay : a.$2.index.compareTo(b.$2.index);
    });
  return ReportPdf(
    title: 'Ledger',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'ledger', from, to),
    columns: const [
      ReportPdfColumn('Date', flex: 1.4),
      ReportPdfColumn('Category', flex: 1.4),
      ReportPdfColumn('Gross', numeric: true),
      ReportPdfColumn('Discount', numeric: true),
      ReportPdfColumn('Taxable', numeric: true),
      ReportPdfColumn('Tax', numeric: true),
      ReportPdfColumn('Net', numeric: true),
    ],
    rows: [
      for (final k in keys)
        [formatDate(k.$1), k.$2.label, ...byDayCategory[k]!.money],
    ],
    totals: rows.isEmpty ? null : ['Total', '', ...total.money],
    notes: rows.isEmpty
        ? const []
        : [
            'Tax by category',
            for (final c in LedgerCategory.values)
              if (byCategory[c] != null)
                '${c.label}: taxable ${formatMoney(byCategory[c]!.taxable)}, '
                    'tax ${formatMoney(byCategory[c]!.tax)}',
          ],
    emptyMessage: 'No revenue in this period.',
  );
}

/// `Cash · R-17`, `Online`, both joined with ` + `, or `—`.
String _paidBy(SettlementRow r) {
  final desk = [r.deskMethod?.label, r.deskReference].whereType<String>().join(' · ');
  final parts = [
    if (r.balanceOnline != 0) 'Online',
    if (desk.isNotEmpty) desk,
  ];
  return parts.isEmpty ? '—' : parts.join(' + ');
}

/// Settlements, condensed to fit A4 landscape: the whole bill, advance,
/// balance (online + desk), how the balance was paid, and outstanding.
ReportPdf settlementsPdf(
  FinanceResort resort,
  DateTime from,
  DateTime to,
  List<SettlementRow> rows,
) {
  String money(num Function(SettlementRow) pick) =>
      formatMoney(_sum(rows.map(pick)));
  return ReportPdf(
    title: 'Settlements',
    resortName: resort.name,
    gstinLabel: gstinLabel(resort),
    periodLabel: _period(from, to),
    fileName: financePdfFileName(resort.slug, 'settlements', from, to),
    columns: const [
      ReportPdfColumn('Guest', flex: 1.6),
      ReportPdfColumn('Unit', flex: 1.2),
      ReportPdfColumn('Stay', flex: 1.8),
      ReportPdfColumn('Room', numeric: true),
      ReportPdfColumn('Cleaning', numeric: true),
      ReportPdfColumn('Tax', numeric: true, flex: 1.3),
      ReportPdfColumn('Food', numeric: true),
      ReportPdfColumn('Activities', numeric: true),
      ReportPdfColumn('Total', numeric: true),
      ReportPdfColumn('Advance', numeric: true),
      ReportPdfColumn('Balance', numeric: true),
      ReportPdfColumn('Paid by', flex: 1.4),
      ReportPdfColumn('Outstanding', numeric: true),
    ],
    rows: [
      for (final r in rows)
        [
          r.guestName,
          r.unitName,
          '${formatDate(r.arrival)} – ${formatDate(r.departure)}',
          formatMoney(r.room),
          formatMoney(r.cleaningFee),
          r.taxPct == 0
              ? formatMoney(r.tax)
              : '${formatMoney(r.tax)} (${formatPct(r.taxPct)}%)',
          formatMoney(r.food),
          formatMoney(r.activities),
          formatMoney(r.total),
          formatMoney(r.advancePaid),
          formatMoney(r.balanceOnline + r.balanceDesk),
          _paidBy(r),
          formatMoney(r.outstanding),
        ],
    ],
    totals: rows.isEmpty
        ? null
        : [
            'Total',
            '',
            '',
            money((r) => r.room),
            money((r) => r.cleaningFee),
            money((r) => r.tax),
            money((r) => r.food),
            money((r) => r.activities),
            money((r) => r.total),
            money((r) => r.advancePaid),
            money((r) => r.balanceOnline + r.balanceDesk),
            '',
            money((r) => r.outstanding),
          ],
    emptyMessage: 'No checkouts in this period.',
  );
}
```

- [ ] **Step 4: Run to see it pass**

Run: `flutter test test/features/finance/finance_pdf_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze
dart format lib/features/finance/finance_pdf.dart test/features/finance/finance_pdf_test.dart
git add lib/features/finance/finance_pdf.dart test/features/finance/finance_pdf_test.dart
git commit -m "feat(finance): Collections, Ledger and Settlements as printable report tables

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Export PDF on the Finance screen and the owner export centre

**Files:**
- Modify: `lib/features/finance/finance_screen.dart` (`_FinanceScreenState`: new `_pdfBusy`, `_pdfFor`, `_exportPdf`; AppBar `actions`)
- Modify: `lib/features/owner/owner_reports_screen.dart` (`_OwnerReportsScreenState`: new `_pdfBusy`, `_exportFinancePdf`; the three finance tiles; the section label; `_ReportTile`)
- Test: `test/features/finance/finance_pdf_export_test.dart`, `test/features/owner/owner_reports_pdf_test.dart`

**Interfaces:**
- Consumes: `collectionsPdf`, `ledgerPdf`, `settlementsPdf` (Task 6); `pdfExporterProvider`, `pdfDelivererProvider`, `ReportPdf` (Task 1); `financeSummaryProvider`, `collectionsProvider`, `ledgerProvider`, `settlementsProvider` (`lib/features/finance/providers.dart`); `financeSourceProvider`; test fakes `FakeFinanceSource`, `FakePdfExporter`, `PdfDeliveries`.
- Produces: Finance AppBar `IconButton(key: Key('finance-export-pdf'), tooltip: 'Export PDF')` on the Collections/Ledger/Settlements tabs; owner tiles' `Export PDF` icon buttons on Collections/Ledger/Settlements.

- [ ] **Step 1: Write the failing Finance screen tests**

`test/features/finance/finance_pdf_export_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_screen.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_pdf_exporter.dart';

const _resort = ResortMembership(
    propertyId: 'p1', resortName: 'Resort R', role: ResortRole.accountant);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _resort;
}

final _august = DateTimeRange(start: DateTime(2026, 8, 1), end: DateTime(2026, 8, 31));

Future<void> _pump(
  WidgetTester tester, {
  required FakeFinanceSource source,
  required FakePdfExporter exporter,
  required PdfDeliveries deliveries,
}) async {
  tester.view.physicalSize = const Size(420, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      pdfExporterProvider.overrideWithValue(exporter),
      pdfDelivererProvider.overrideWithValue(deliveries.deliver),
    ],
    child: MaterialApp(home: FinanceScreen(initialRange: _august)),
  ));
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final tab = find.widgetWithText(Tab, label);
  await tester.ensureVisible(tab);
  await tester.pumpAndSettle();
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Today has no PDF export; the three reports do', (tester) async {
    await _pump(tester,
        source: FakeFinanceSource(),
        exporter: FakePdfExporter(),
        deliveries: PdfDeliveries());

    expect(find.byKey(const Key('finance-export-pdf')), findsNothing);
    expect(find.byKey(const Key('finance-export')), findsOneWidget);
    for (final label in ['Collections', 'Ledger', 'Settlements']) {
      await _openTab(tester, label);
      expect(find.byTooltip('Export PDF'), findsOneWidget, reason: label);
    }
  });

  for (final (label, title, report) in [
    ('Collections', 'Collections', 'collections'),
    ('Ledger', 'Ledger', 'ledger'),
    ('Settlements', 'Settlements', 'settlements'),
  ]) {
    testWidgets('$label exports its own PDF for the chosen range', (tester) async {
      final exporter = FakePdfExporter();
      final deliveries = PdfDeliveries();
      await _pump(tester,
          source: FakeFinanceSource()
            ..collectionRows = [collectionRow(amount: 5000)]
            ..ledgerRows = [ledgerRow(gross: 1000)]
            ..settlementRows = [settlementRow(room: 1000)],
          exporter: exporter,
          deliveries: deliveries);
      await _openTab(tester, label);

      await tester.tap(find.byKey(const Key('finance-export-pdf')));
      await tester.pumpAndSettle();

      final pdf = exporter.reports.single;
      expect(pdf.title, title);
      expect(pdf.rows, isNotEmpty);
      expect(deliveries.files.single.$1, 'fin-r-$report-2026-08-01-2026-08-31.pdf');
      expect(find.text('PDF exported.'), findsOneWidget);
    });
  }

  testWidgets('a platform that cannot take the file says so', (tester) async {
    await _pump(tester,
        source: FakeFinanceSource(),
        exporter: FakePdfExporter(),
        deliveries: PdfDeliveries(delivers: false));
    await _openTab(tester, 'Collections');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(find.text("PDF export isn't available on this platform yet."), findsOneWidget);
  });

  testWidgets('a rendering failure is reported, not thrown', (tester) async {
    await _pump(tester,
        source: FakeFinanceSource(),
        exporter: FakePdfExporter()..error = StateError('font'),
        deliveries: PdfDeliveries());
    await _openTab(tester, 'Ledger');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't create the PDF. Try again."), findsOneWidget);
  });

  testWidgets('a report that failed to load exports nothing', (tester) async {
    final exporter = FakePdfExporter();
    await _pump(tester,
        source: FakeFinanceSource()..settlementsError = const NotAMember(),
        exporter: exporter,
        deliveries: PdfDeliveries());
    await _openTab(tester, 'Settlements');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pumpAndSettle();

    expect(find.text("This report didn't load, so there is nothing to export."),
        findsOneWidget);
    expect(exporter.reports, isEmpty);
  });

  testWidgets('a second tap while a PDF is being made does nothing', (tester) async {
    final hold = Completer<void>();
    final exporter = FakePdfExporter()..hold = hold;
    final deliveries = PdfDeliveries();
    await _pump(tester,
        source: FakeFinanceSource(), exporter: exporter, deliveries: deliveries);
    await _openTab(tester, 'Collections');

    await tester.tap(find.byKey(const Key('finance-export-pdf')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finance-export-pdf')), warnIfMissed: false);
    await tester.pump();
    expect(exporter.reports, hasLength(1));

    hold.complete();
    await tester.pumpAndSettle();
    expect(deliveries.files, hasLength(1));
  });
}
```

- [ ] **Step 2: Write the failing owner export-centre tests**

`test/features/owner/owner_reports_pdf_test.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/current_resort.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/core/pdf/pdf_delivery.dart';
import 'package:pasala/core/pdf/pdf_exporter.dart';
import 'package:pasala/data/models/resort_membership.dart';
import 'package:pasala/data/repositories/finance_repository.dart';
import 'package:pasala/features/finance/finance_tables.dart';
import 'package:pasala/features/owner/owner_reports_screen.dart';

import '../../support/fake_finance_source.dart';
import '../../support/fake_pdf_exporter.dart';

const _ownerM =
    ResortMembership(propertyId: 'p1', resortName: 'Resort R', role: ResortRole.owner);

class _FixedResort extends CurrentResort {
  @override
  ResortMembership? build() => _ownerM;
}

/// The screen opens on this month; the file names follow it.
String _month() {
  final now = DateTime.now();
  return '${isoDate(DateTime(now.year, now.month, 1))}-'
      '${isoDate(DateTime(now.year, now.month + 1, 0))}';
}

Future<void> _pump(WidgetTester tester, FakeFinanceSource source,
    FakePdfExporter exporter, PdfDeliveries deliveries) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      financeSourceProvider.overrideWithValue(source),
      currentResortProvider.overrideWith(_FixedResort.new),
      pdfExporterProvider.overrideWithValue(exporter),
      pdfDelivererProvider.overrideWithValue(deliveries.deliver),
    ],
    child: const MaterialApp(home: OwnerReportsScreen()),
  ));
  await tester.pumpAndSettle();
}

Finder _pdfOn(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title), matching: find.byTooltip('Export PDF'));

void main() {
  testWidgets('the three finance tiles offer PDF next to CSV; the others do not',
      (tester) async {
    await _pump(tester, FakeFinanceSource(), FakePdfExporter(), PdfDeliveries());

    expect(find.text('EXPORT'), findsOneWidget);
    for (final title in ['Collections', 'Ledger', 'Settlements']) {
      expect(_pdfOn(title), findsOneWidget, reason: title);
    }
    for (final title in ['Revenue', 'Occupancy', 'Food & activity sales', 'Expenses']) {
      expect(_pdfOn(title), findsNothing, reason: title);
    }
    expect(find.byTooltip('Export CSV'), findsNWidgets(7));
  });

  for (final (title, report) in [
    ('Collections', 'collections'),
    ('Ledger', 'ledger'),
    ('Settlements', 'settlements'),
  ]) {
    testWidgets('$title exports this month as PDF', (tester) async {
      final exporter = FakePdfExporter();
      final deliveries = PdfDeliveries();
      await _pump(tester, FakeFinanceSource(), exporter, deliveries);

      await tester.tap(_pdfOn(title));
      await tester.pumpAndSettle();

      expect(exporter.reports.single.title, title);
      expect(deliveries.files.single.$1, 'fin-r-$report-${_month()}.pdf');
      expect(find.text('PDF exported.'), findsOneWidget);
    });
  }

  testWidgets('a refusal is shown and nothing is exported', (tester) async {
    final exporter = FakePdfExporter();
    await _pump(tester, FakeFinanceSource()..summaryError = const NotAMember(),
        exporter, PdfDeliveries());

    await tester.tap(_pdfOn('Ledger'));
    await tester.pumpAndSettle();

    expect(find.text('You no longer have access to this resort.'), findsOneWidget);
    expect(exporter.reports, isEmpty);
  });
}
```

- [ ] **Step 3: Run to see them fail**

Run: `flutter test test/features/finance/finance_pdf_export_test.dart test/features/owner/owner_reports_pdf_test.dart`
Expected: FAIL — no `finance-export-pdf` key, no "Export PDF" tooltips, no "EXPORT" label.

- [ ] **Step 4: Add Export PDF to the Finance screen**

In `lib/features/finance/finance_screen.dart` add imports:
```dart
import '../../core/pdf/pdf_delivery.dart';
import '../../core/pdf/pdf_exporter.dart';
import '../../core/pdf/report_pdf.dart';
import 'finance_pdf.dart';
```
In `_FinanceScreenState`, after `late DateTimeRange _range = …;` add:
```dart
  /// True while a PDF is being made: the button is disabled meanwhile.
  bool _pdfBusy = false;
```
After `_export`, add:
```dart
  /// The PDF of [tab] (Collections, Ledger or Settlements), from what its
  /// provider already holds, like [_rowsFor].
  AsyncValue<ReportPdf> _pdfFor(int tab, FinanceSummary summary, ReportFilter filter) =>
      switch (tab) {
        1 => ref.read(collectionsProvider(filter)).whenData(
            (rows) => collectionsPdf(summary.resort, filter.from, filter.to, rows)),
        2 => ref.read(ledgerProvider(filter)).whenData(
            (rows) => ledgerPdf(summary.resort, filter.from, filter.to, rows)),
        3 => ref.read(settlementsProvider(filter)).whenData(
            (rows) => settlementsPdf(summary.resort, filter.from, filter.to, rows)),
        _ => throw StateError('Finance has no PDF for tab $tab'),
      };

  /// Exports the report on screen as PDF: nothing until both the summary
  /// (name, slug, GSTIN) and the report have loaded; one at a time.
  Future<void> _exportPdf(String propertyId) async {
    if (_pdfBusy) return;
    final summaryAsync = ref.read(financeSummaryProvider(propertyId));
    final summary = summaryAsync.value;
    if (summary == null) {
      _show(summaryAsync.hasError ? _failed : _loading);
      return;
    }
    final reportAsync =
        _pdfFor(_tabController.index, summary, _filterFor(propertyId));
    final report = reportAsync.value;
    if (report == null) {
      _show(reportAsync.hasError ? _failed : _loading);
      return;
    }
    final exporter = ref.read(pdfExporterProvider);
    final deliver = ref.read(pdfDelivererProvider);
    setState(() => _pdfBusy = true);
    try {
      final delivered = await deliver(report.fileName, await exporter.report(report));
      if (mounted) {
        _show(delivered
            ? 'PDF exported.'
            : "PDF export isn't available on this platform yet.");
      }
    } catch (_) {
      if (mounted) _show("Couldn't create the PDF. Try again.");
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }
```
In `build`, replace the AppBar `actions: [ IconButton(key: const Key('finance-export'), …), ]` list with:
```dart
        actions: [
          // Collections, Ledger and Settlements only (spec Decision 9).
          if (!onToday)
            IconButton(
              key: const Key('finance-export-pdf'),
              tooltip: 'Export PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _pdfBusy ? null : () => _exportPdf(propertyId),
            ),
          IconButton(
            key: const Key('finance-export'),
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => _export(propertyId),
          ),
        ],
```
Also update the class doc comment's last sentence to: "…with pull-to-refresh, an Export CSV action for the tab on screen, and Export PDF on Collections, Ledger and Settlements."

- [ ] **Step 5: Add PDF to the owner export centre**

In `lib/features/owner/owner_reports_screen.dart` add imports:
```dart
import '../../core/pdf/pdf_delivery.dart';
import '../../core/pdf/pdf_exporter.dart';
import '../../core/pdf/report_pdf.dart';
import '../finance/finance_pdf.dart';
```
In `_OwnerReportsScreenState`, after `DateTimeRange _range = _currentMonth();` add:
```dart
  bool _pdfBusy = false;
```
After `_exportFinance`, add:
```dart
  /// A finance report as PDF: a fresh query per export, like
  /// [_exportFinance]; one at a time.
  Future<void> _exportFinancePdf(_OwnerReportKind kind, String propertyId) async {
    if (_pdfBusy) return;
    final source = ref.read(financeSourceProvider);
    final exporter = ref.read(pdfExporterProvider);
    final deliver = ref.read(pdfDelivererProvider);
    final from = _range.start;
    final to = _range.end;
    setState(() => _pdfBusy = true);
    try {
      final resort = (await source.summary(propertyId)).resort;
      final ReportPdf report = switch (kind) {
        _OwnerReportKind.collections => collectionsPdf(
            resort, from, to, await source.collections(from, to, propertyId)),
        _OwnerReportKind.ledger =>
          ledgerPdf(resort, from, to, await source.ledger(from, to, propertyId)),
        _ => settlementsPdf(
            resort, from, to, await source.settlements(from, to, propertyId)),
      };
      final delivered = await deliver(report.fileName, await exporter.report(report));
      if (mounted) {
        _showMessage(delivered
            ? 'PDF exported.'
            : "PDF export isn't available on this platform yet.");
      }
    } on BookingFailure catch (e) {
      if (mounted) _showMessage(FailureView.messageFor(e));
    } catch (_) {
      if (mounted) _showMessage("Couldn't create the PDF. Try again.");
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }
```
In `build`, next to `void export(_OwnerReportKind kind) => …;` add:
```dart
    void exportPdf(_OwnerReportKind kind) => _exportFinancePdf(kind, resort.propertyId);
```
Change the section label `Text('EXPORT AS CSV', …)` to `Text('EXPORT', …)`. On the Collections, Ledger and Settlements `_ReportTile`s add:
```dart
            onExportPdf: () => exportPdf(_OwnerReportKind.collections),
            pdfBusy: _pdfBusy,
```
(with `.ledger` / `.settlements` on the other two). Replace `_ReportTile` with:
```dart
class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onExport,
    this.onExportPdf,
    this.pdfBusy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onExport;

  /// Shows an Export PDF button next to CSV when set.
  final VoidCallback? onExportPdf;
  final bool pdfBusy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final csv = IconButton(
      tooltip: 'Export CSV',
      icon: const Icon(Icons.download_outlined),
      onPressed: onExport,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: onExportPdf == null
            ? csv
            : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Export PDF',
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: pdfBusy ? null : onExportPdf,
                ),
                csv,
              ]),
      ),
    );
  }
}
```
Update the class doc comment: "…all exportable as CSV through `csv_export.dart` and [csvDownloaderProvider], and the three finance reports as PDF too (`finance_pdf.dart`)."

- [ ] **Step 6: Run the new and existing tests**

Run:
```bash
flutter test test/features/finance test/features/owner
```
Expected: PASS, including the existing `finance_screen_test.dart` and `owner_reports_screen_test.dart`.

- [ ] **Step 7: Analyze, format the new tests, commit**

```bash
flutter analyze
dart format test/features/finance/finance_pdf_export_test.dart test/features/owner/owner_reports_pdf_test.dart
git add lib/features/finance/finance_screen.dart lib/features/owner/owner_reports_screen.dart test/features/finance/finance_pdf_export_test.dart test/features/owner/owner_reports_pdf_test.dart
git commit -m "feat(finance): Export PDF next to CSV for Collections, Ledger and Settlements

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Integration — full suite, web build, Playwright, docs

**Files:**
- Modify: `e2e/support/accountant-data.ts` (export the desk reservation id)
- Modify: `e2e/tests/accountant.spec.ts` (three PDF tests)
- Modify: `README.md` (a short "Invoices and PDF exports" section)

**Interfaces:**
- Consumes: everything above; e2e helpers `login`, `goTo` (`e2e/support/index.ts`), `switchFinanceTab`, `narrow`, `bodyLines` (local to `accountant.spec.ts`), `deskGuest`, `setupAccountantFixtures`.
- Produces: nothing new for other tasks.

- [ ] **Step 1: Run the whole Flutter suite and analyzer**

```bash
flutter pub get
flutter analyze
flutter test
```
Expected: analyze shows only the 2 baseline infos; every test passes. Fix any failure in the task that owns the file before going on.

- [ ] **Step 2: Build for the web**

```bash
bash e2e/build-app.sh
```
Expected: `✓ Built build/web`. (`printing` must compile for web even though the web path never calls it.)

- [ ] **Step 3: Export the desk reservation id**

In `e2e/support/accountant-data.ts` replace
```ts
/** Resort A, Tree House: yesterday -> today, already checked out. */
const RESERVATION_ID = 'e2eacc00-0000-4000-8000-000000000002';
```
with
```ts
/** Resort A, Tree House: yesterday -> today, already checked out. */
export const DESK_RESERVATION_ID = 'e2eacc00-0000-4000-8000-000000000002';
const RESERVATION_ID = DESK_RESERVATION_ID;
```

- [ ] **Step 4: Add the Playwright checks**

In `e2e/tests/accountant.spec.ts`, extend the imports:
```ts
import { expect, test, type Locator, type Page } from '@playwright/test';
import { goTo, landingPath, login } from '../support/index.ts';
import {
  DESK_RESERVATION_ID,
  deskGuest,
  setupAccountantFixtures,
  teardownAccountantFixtures,
} from '../support/accountant-data.ts';
```
Add a helper next to `bodyLines`:
```ts
/** Clicks [button], returns the download's file name and first five bytes. */
async function downloadVia(page: Page, button: Locator): Promise<{ name: string; head: string }> {
  const [download] = await Promise.all([page.waitForEvent('download'), button.click()]);
  const path = await download.path();
  expect(path).toBeTruthy();
  return {
    name: download.suggestedFilename(),
    head: readFileSync(path!).subarray(0, 5).toString('latin1'),
  };
}
```
and, inside `test.describe('Accountant (Resort A)', …)`, after the CSV test:
```ts
  test('Collections exports a PDF next to the CSV', async ({ page }) => {
    await login(page, accountant);
    await narrow(page);
    await switchFinanceTab(
      page,
      'Collections',
      (ls) => ls.includes('No collections in this period') || ls.some((l) => l.startsWith('Total Online')),
    );

    const file = await downloadVia(page, page.getByRole('button', { name: 'Export PDF', exact: true }));

    expect(file.name).toMatch(/^e2e-a-collections-\d{4}-\d{2}-\d{2}-\d{4}-\d{2}-\d{2}\.pdf$/);
    expect(file.head).toBe('%PDF-');
    const lines = await bodyLines(page);
    expect(lines.some((l) => l.includes('PDF exported.'))).toBe(true);
  });

  test('a settlement row downloads that booking\'s invoice', async ({ page }) => {
    await login(page, accountant);
    await narrow(page);
    await switchFinanceTab(
      page,
      'Settlements',
      (ls) => ls.includes('No checkouts in this period') || ls.some((l) => l.includes(deskGuest.fullName)),
    );

    const file = await downloadVia(page, page.getByRole('button', { name: 'Invoice PDF', exact: true }).first());

    expect(file.name).toBe('invoice-E2E-A-E2EACC00.pdf');
    expect(file.head).toBe('%PDF-');
  });

  test('the guest downloads the same invoice from their booking', async ({ page }) => {
    await login(page, deskGuest);
    await goTo(page, `/booking-detail/${DESK_RESERVATION_ID}`);

    const file = await downloadVia(
      page,
      page.getByRole('button', { name: 'Download invoice (PDF)', exact: true }),
    );

    expect(file.name).toBe('invoice-E2E-A-E2EACC00.pdf');
    expect(file.head).toBe('%PDF-');
  });
```
The Settlements test uses `.first()` because only the desk-paid booking is checked out this month in the fixture world; if other specs add checkouts, scope the locator to the card containing `deskGuest.fullName`.

- [ ] **Step 5: Run the accountant spec against the local stack**

```bash
supabase start
cd e2e && npx playwright test tests/accountant.spec.ts
```
Expected: all accountant tests pass, including the three new ones. If the existing Settlements test's `expect(row).toMatch(/Settled$/)` now fails because the card's merged semantics line gained the "Invoice PDF" button, change that one assertion to `expect(row).toMatch(/Settled/)` (the button is a separate semantics node after "Settled"); do not change the app. Then run the whole suite:
```bash
cd e2e && npx playwright test
```
Expected: everything that passed before still passes (the known time-of-day pgTAP failures are not part of Playwright).

- [ ] **Step 6: Document it**

Append to `README.md`:
```markdown
## Invoices and PDF exports

- **Booking invoice (PDF)** — on a checked-in or checked-out booking's detail
  screen (guests from My Bookings, owners/admins from Admin → Bookings), on the
  Final Invoice screen after checkout, and per row in Finance → Settlements.
  Built client-side from the stored quote, the booking's food orders,
  activity bookings and payments, checked against `current_charges`; a
  checked-in stay gets a "Provisional bill". Invoice number:
  `<RESORT-SLUG>-<first 8 hex of the booking id>`.
- **Report PDFs** — Finance → Collections / Ledger / Settlements ("Export PDF"
  next to "Export CSV") and Owner → Reports.
- Web downloads the file; Android/iOS/desktop open the share sheet
  (`package:printing`). Fonts: Noto Sans (SIL OFL 1.1, `assets/fonts/`).
```

- [ ] **Step 7: Commit**

```bash
git add e2e/support/accountant-data.ts e2e/tests/accountant.spec.ts README.md
git commit -m "test(e2e): invoice and report PDF downloads; document PDF exports

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

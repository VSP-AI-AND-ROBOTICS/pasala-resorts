# PDF Invoices and Report PDFs (P2) — Design

## Why

The gap-closing round (product owner, 2026-09-25, "OK all ... auto approve")
asks for printable documents in two places:

- **A booking invoice.** Today a guest sees an on-screen "Final Invoice"
  (`lib/features/stay/final_invoice_screen.dart`, route
  `/my-stay/invoice/:id`) with three totals from `current_charges` —
  "Farmhouse stay", "Food", "Activities" — and its own header comment says
  "no PDF export". Nobody can take away a document with the resort's name,
  address and GSTIN, the invoice number, the charge lines with tax, and how
  the bill was paid. Reception lands on that same screen after a desk
  checkout (`CheckoutScreen._checkout` in `lib/features/stay/checkout_screen.dart`
  does `context.go('/my-stay/invoice/<id>')`), and owners and accountants
  have no per-booking document at all.
- **Report PDFs.** The Finance screen (`/finance`,
  `lib/features/finance/finance_screen.dart`) and the owner export centre
  (`/owner/reports`, `lib/features/owner/owner_reports_screen.dart`) export
  Collections, Ledger and Settlements as CSV only
  (`lib/features/finance/finance_csv.dart`, delivered through
  `csvDownloaderProvider`). A CSV is for spreadsheets; an owner handing a
  month's settlements to an auditor wants a paginated PDF.

Everything the documents need already exists server-side: the stored
quote on `reservations.quote` (lines, `subtotal`, `cleaning_fee`, `coupon`,
`tax_pct`, `tax_amount`, `total`, built by `get_quote` in
`0045_resort_functions.sql`), `food_orders.total`,
`activity_bookings.amount`, `payments` (with `method`, `reference`,
`gateway_ref`, `kind` since `0048_finance_ledger.sql`), `current_charges`
(`0045`), the resort's `properties.name/slug/address/gstin`, and the four
finance report functions (`report_collections`, `report_ledger`,
`report_settlements`, `finance_summary`, `0048`).

## Decisions (auto-approved 2026-09-25; judgment calls recorded here)

1. **Packages `pdf` + `printing`.** Documents are built client-side with
   `package:pdf` (widgets API). Delivery: on the web the bytes are downloaded
   through a Blob anchor exactly like `csv_download_web.dart` (so Playwright
   sees a real `download` event); on Android, iOS and desktop
   `Printing.sharePdf` opens the platform share sheet (save, print, send).
   Nothing is uploaded or stored.
2. **No migration, no new table, no new SQL function.** The invoice reads,
   under the RLS that already applies to the viewer: `reservations` with
   embeds `properties(name, slug, address, gstin)`, `units(name)` and
   `profiles!reservations_customer_id_fkey(full_name, phone)`; non-cancelled
   `food_orders` and `activity_bookings` of the reservation; succeeded
   `payments`; and `current_charges(p_reservation_id)`. The guest reads all
   of these as "the guest who owns the reservation"; owner, admin, staff and
   accountant read them as members of its resort (`0044_resort_policies.sql`).
   Report PDFs reuse the rows the Finance screen already fetched through
   `FinanceSource`.
3. **`current_charges` is the authority on totals.** Category lines come
   from the rows above with exactly `current_charges`' filters (food orders
   and activity bookings with `status <> 'cancelled'`, payments with
   `status = 'succeeded'`). If the lines do not add up to
   `current_charges.total` within ₹0.01 (e.g. a food order landed between two
   reads) the invoice is refused with "The bill changed while the invoice was
   being prepared. Try again." — never a document that contradicts itself.
   Paid and amount due are `current_charges.paid` and `.balance`.
4. **Invoice number** = the resort slug upper-cased, a hyphen, and the first
   8 hex digits of the reservation id upper-cased: slug `pasala`, id
   `3f2a9c1b-…` → `PASALA-3F2A9C1B`. Stable for every viewer, derived only
   from stored ids. File name `invoice-<NUMBER>.pdf`.
5. **Title and date.** A checked-out booking gets **"Invoice"**, dated at
   `checked_out_at`. A checked-in booking gets a **"Provisional bill"**, dated
   now, with the note "The stay is still in progress, so this bill may change
   before checkout." Holds, pending, confirmed and cancelled bookings, admin
   blocks and OTA rows have no invoice ("An invoice is available once the
   guest has checked in." / "Only guest bookings have an invoice."). This is
   not a GST "Tax Invoice" (no SAC codes, place of supply or CGST/SGST split).
6. **Lines and tax per category.**
   - **Room** — `quote.subtotal` (nightly rates plus extra-guest charges),
     labelled "Room (N nights)" (N = quote lines) or "Room (day use)" for a
     slot booking (`reservations.slot_type_id` set).
   - **Cleaning fee** — `quote.cleaning_fee` (omitted when zero with zero tax).
   - **Coupon (CODE)** — minus `quote.coupon.discount`, no tax of its own.
   - Room tax (`quote.tax_amount`, additive, charged on subtotal + cleaning
     fee − discount) is split exactly as `report_ledger` splits it: the room
     line gets `round((subtotal − min(discount, subtotal)) × tax_pct / 100, 2)`,
     the cleaning-fee line the rest. When a coupon and tax both apply, the
     note "Tax is charged on the room and cleaning fee after the coupon
     discount." explains why the Tax column does not equal Amount × rate.
   - **Food & Drink** (food orders) and **Spa & Activities** (activity
     bookings) — prices are tax-inclusive, so Amount = total − stored tax and
     Tax = stored tax. The stored tax is the P4 columns `tax_amount` (and
     `tax_pct`) on `food_orders` and `activity_bookings`, read from `select *`
     when present and taken as 0 when absent — P2 works before P4 is merged
     and shows F&B/spa tax automatically after it. The rate is shown only
     when every row of the category has the same non-zero `tax_pct`.
   - Every line shows Amount (excl. tax), Tax (with rate) and Total; the
     invoice shows Subtotal (excl. tax), Tax and Total.
7. **Payments.** Every succeeded payment, oldest first: Advance/Balance,
   method label (Online, Cash, Card, UPI, Bank transfer, Other), reference
   (the desk receipt/UTR in `payments.reference`; the gateway's id in
   `payments.gateway_ref` for online payments; omitted when blank), date and
   amount. Then Total paid and **Amount due**.
8. **Where the invoice is offered.**
   - **Booking detail** (`/booking-detail/:id`,
     `lib/features/account/booking_detail_screen.dart`) for a guest booking
     that is checked in or checked out: "Download invoice (PDF)". The guest
     reaches it from My Bookings; owners and admins from `/admin/bookings`,
     which already opens the same screen.
   - **Final Invoice screen** (`/my-stay/invoice/:id`): the same button above
     "Leave a review" — the guest after self-checkout, and reception after a
     desk checkout (their current landing). P5 later sends reception back to
     `/admin/check-out` with a "Download invoice" action; it reuses this
     project's `downloadInvoicePdf`, and P2 does not touch
     `checkout_screen.dart`.
   - **Finance → Settlements** rows (owner, admin, accountant; the accountant
     cannot open `/admin/bookings`): an "Invoice PDF" icon button per row, in
     both the phone card and the wide table.
9. **Report PDFs.** Finance gets an **Export PDF** icon button (tooltip
   "Export PDF") next to Export CSV on the Collections, Ledger and
   Settlements tabs (hidden on Today, which the decision does not list). The
   owner export centre gets an Export PDF button next to Export CSV on the
   same three tiles, and its section label becomes "EXPORT". PDFs are A4
   landscape, with the resort name, GSTIN label, report title and period on
   every page, a repeated table header, a bold totals row, "Page x of y" and
   a generated-at stamp. They use human-readable labels like the on-screen
   tables, not the CSV's wire values:
   - Collections: Date, Online, Cash, Card, UPI, Bank, Other, Refunds, Net —
     one row per day (`collectionsByDay`) and a totals row
     (`collectionsTotal`).
   - Ledger: Date, Category, Gross, Discount, Taxable, Tax, Net — one row per
     day and category (sources summed), a totals row, and a "Tax by category"
     note block (taxable and tax per category over the period).
   - Settlements: Guest, Unit, Stay, Room, Cleaning, Tax, Food, Activities,
     Total, Advance, Balance (online + desk), Paid by (desk method ·
     reference, or Online), Outstanding — and a totals row.
   File name `<slug>-<report>-<from>-<to>.pdf`, the CSV name with `.pdf`.
10. **Fonts.** Noto Sans Regular and Bold (SIL OFL 1.1, `assets/fonts/` with
    `OFL.txt`) are bundled so the ₹ sign renders; money prints as
    `₹1,080.00` like `formatMoney`. Characters the font does not have
    (Devanagari, emoji) print as `?` rather than failing the document.
11. **A resort the viewer cannot read** (a guest of a suspended, archived or
    hidden resort — `properties_read` shows guests only active resorts)
    has no header, number or GSTIN, so the invoice is refused with "This
    resort isn't taking bookings right now, so its invoice can't be issued.
    Contact the resort." Staff always read their own resort.
12. **Dates** print in the device's local time, like every other date in the
    app (`formatDate`, `d MMM yyyy`).
13. **Seams for tests**: `InvoiceSource` (`invoiceSourceProvider`),
    `PdfExporter` (`pdfExporterProvider`) and `PdfDeliverer`
    (`pdfDelivererProvider`), each with a fake in `test/support/`, like
    `FinanceSource`/`csvDownloaderProvider` today.

## Data model

None. No migration, table, column, policy or SQL function is added or
changed; no pgTAP file. The only "contract" with another project is
Decision 6's read of the P4 columns `food_orders.tax_amount/tax_pct` and
`activity_bookings.tax_amount/tax_pct`, which are optional.

## Functions

No new SQL functions. Used as they are:

- `current_charges(p_reservation_id uuid) returns jsonb` (`0045`) — the
  guest's own reservation, or `owner, admin, staff, accountant` at its resort.
- `report_collections`, `report_ledger`, `report_settlements`,
  `finance_summary` (`0048`) — owner, admin, accountant; already called
  through `FinanceRepository`.

## App

- **Packages**: `pdf`, `printing` in `pubspec.yaml`; fonts
  `assets/fonts/NotoSans-Regular.ttf`, `NotoSans-Bold.ttf`, `OFL.txt`.
- `lib/core/pdf/`:
  - `pdf_fonts.dart` — `PdfFonts` (regular, bold, `theme`, `supports(rune)`,
    `safe(text)`), `loadPdfFonts()` from the asset bundle.
  - `pdf_format.dart` — `pdfMoney(num)` (`₹1,080.00`), `pdfDate(DateTime)`.
  - `pdf_delivery.dart` — `typedef PdfDeliverer`, `pdfDelivererProvider`;
    `pdf_deliver.dart` conditional export of `deliverPdf` from
    `pdf_deliver_web.dart` (Blob download) or `pdf_deliver_share.dart`
    (`Printing.sharePdf`).
  - `report_pdf.dart` — the `ReportPdf`/`ReportPdfColumn` model.
  - `report_pdf_renderer.dart` — `buildReportDocument`, `renderReportPdf`.
  - `invoice_pdf_renderer.dart` — `buildInvoiceDocument`, `renderInvoicePdf`.
  - `pdf_exporter.dart` — `PdfExporter` (`invoice(Invoice)`,
    `report(ReportPdf)`), `PasalaPdfExporter` (loads fonts once),
    `pdfExporterProvider`.
- `lib/data/models/invoice.dart` — `InvoiceResort`, `InvoiceCharge`,
  `InvoicePaymentKind`, `InvoicePayment`, `InvoiceInput`, `InvoiceLineKind`,
  `InvoiceLine`, `Invoice`.
- `lib/data/models/invoice_builder.dart` — `invoiceNumber`, `buildInvoice`
  (pure; Decisions 3–7, 11).
- `lib/data/repositories/invoice_repository.dart` — `InvoiceSource`,
  `InvoiceRepository` (the five reads of Decision 2 in parallel, then
  `buildInvoice`; `inputFrom` parses rows), `invoiceRepositoryProvider`,
  `invoiceSourceProvider`.
- `lib/features/invoice/invoice_pdf_button.dart` — `downloadInvoicePdf(context,
  ref, reservationId)` and `InvoicePdfButton` (full-width "Download invoice
  (PDF)" or an icon "Invoice PDF"; disabled with a spinner while working).
- `lib/features/finance/finance_pdf.dart` — `financePdfFileName`,
  `collectionsPdf`, `ledgerPdf`, `settlementsPdf`.
- Changed screens: `booking_detail_screen.dart`, `final_invoice_screen.dart`,
  `finance_settlements_tab.dart`, `finance_screen.dart`,
  `owner_reports_screen.dart`. No route or role-matrix change.
- Messages: "Invoice <NUMBER> is ready." / "Invoice download isn't available
  on this device yet." / "Couldn't create the invoice PDF. Try again." /
  "PDF exported." / "PDF export isn't available on this platform yet." /
  "Couldn't create the PDF. Try again."; server refusals through
  `FailureView.messageFor`.

## Rules

- Prices are never recomputed: every amount is a stored quote figure, a
  stored row amount/tax, or `current_charges`; the only arithmetic is the
  ledger's own room/cleaning tax split and sums, checked against
  `current_charges.total`.
- No policy is widened; a viewer gets an invoice only for a reservation they
  can already read, and a report PDF only from rows the report functions
  already returned to them.
- One export at a time per button; nothing is cached across taps (every tap
  reads afresh).

## Testing

- Flutter only (no database work): `buildInvoice` (the full fixture with
  coupon, cleaning fee, 12% room tax, 5% food and 18% spa tax; no-tax rows;
  mixed rates; provisional vs final; wrong status; blocks; unreadable resort;
  mismatch; day use; blank guest name; payment references and order);
  `InvoiceRepository.inputFrom` over JSON fixtures (embeds present and
  hidden, optional tax columns, reference choice); the renderers (valid
  `%PDF`, page counts, 800-row reports past the default 20-page limit,
  Devanagari and emoji text); `PdfFonts` (₹ glyph, `safe`, asset loading);
  the three finance builders; widget tests for the invoice button (success,
  refusal, not delivered, exporter failure, double tap), booking detail
  (which statuses show it), Final Invoice, Settlements (card and table), the
  Finance screen and the owner export centre (which tabs/tiles, file names,
  messages).
- Integration: `flutter analyze` (baseline), full `flutter test`,
  `flutter build web`, and Playwright additions in `e2e/tests/accountant.spec.ts`
  — Collections Export PDF downloads `e2e-a-collections-….pdf` starting
  `%PDF`; the Settlements row downloads `invoice-E2E-A-E2EACC00.pdf`; the
  desk-pay guest downloads the same invoice from their booking detail.

## Out of scope

GST-compliant tax-invoice fields and financial-year invoice sequences;
storing, emailing (P7) or regenerating PDFs server-side; Devanagari shaping
or other scripts; a print-preview dialog; PDFs for Revenue, Occupancy, Food &
activity sales and Expenses; the Today tab PDF; the reception post-checkout
flow (P5); walk-in `food_activity_sales` on an invoice (they are not tied to
a booking, as in `current_charges`).

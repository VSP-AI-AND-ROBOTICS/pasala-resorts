import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/quote.dart';

/// Displays a server-computed quote, with a coupon field above the price
/// breakdown. This widget performs no arithmetic: every figure shown --
/// including the discount line -- comes straight from [Quote]/
/// [Quote.coupon], never recomputed in Dart.
class QuoteSheet extends StatefulWidget {
  const QuoteSheet({
    super.key,
    required this.quote,
    required this.onPay,
    required this.busy,
    required this.onApplyCoupon,
    this.couponBusy = false,
    this.couponError,
    this.advancePct = 100,
    this.onPaySplit,
  });

  final Quote quote;
  final VoidCallback onPay;
  final void Function(num amountToPay, bool isSplit)? onPaySplit;
  final num advancePct;
  final bool busy;

  /// Called with the trimmed field text when Apply is tapped. Re-fetching
  /// the quote and deciding success/failure both happen in the parent --
  /// this widget only renders whatever [quote]/[couponBusy]/[couponError]
  /// it's handed next, so a failed apply leaves the previous [quote]
  /// showing exactly as-is (the parent never touches it on failure).
  final Future<void> Function(String code) onApplyCoupon;
  final bool couponBusy;
  final String? couponError;

  @override
  State<QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<QuoteSheet> {
  final _controller = TextEditingController();
  bool _splitPayment = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // Round the advance *up* to the rupee: `confirm_booking` rejects any
    // amount below round(total * advance_pct / 100, 2), so rounding to the
    // nearest rupee could land a few paise short and fail after charging.
    final advanceAmount = math.min(
      (quote.total * widget.advancePct / 100.0).ceilToDouble(),
      quote.total.toDouble(),
    );
    final dueAmount = quote.total - advanceAmount;
    final pct = widget.advancePct;
    final pctLabel = pct == pct.roundToDouble() ? '${pct.toInt()}' : '$pct';

    // `isScrollControlled: true` (booking_screen.dart's `_showQuoteSheet`)
    // lets this sheet grow past the default ~half-screen cap, but on a
    // short viewport the coupon field + full price breakdown + Pay button
    // can still exceed even the full screen height -- without a scroll
    // view here, that overflows ("BOTTOM OVERFLOWED BY n PIXELS") instead
    // of just scrolling. Reproduced live on a short/landscape browser
    // viewport with a multi-night stay (enough price-breakdown rows to
    // push the total past the fold).
    return SingleChildScrollView(
      child: Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Have a coupon?', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('coupon-field'),
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  enabled: !widget.couponBusy,
                  decoration: const InputDecoration(
                    labelText: 'Coupon code',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _apply(),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              OutlinedButton(
                key: const Key('apply-coupon-button'),
                onPressed: widget.couponBusy ? null : _apply,
                child: Text(widget.couponBusy ? 'Applying…' : 'Apply'),
              ),
            ],
          ),
          if (widget.couponError != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              widget.couponError!,
              key: const Key('coupon-error'),
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: Spacing.md),
          const Divider(),
          const SizedBox(height: Spacing.sm),
          Text('Price breakdown', style: textTheme.titleMedium),
          const SizedBox(height: Spacing.md),
          for (final line in quote.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      formatDay(line.date),
                      style: textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: Text(line.label)),
                  Text(formatInr(line.amount)),
                ],
              ),
            ),
          for (final line in quote.lines)
            if (line.extraGuests > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        formatDay(line.date),
                        style: textTheme.bodySmall,
                      ),
                    ),
                    Expanded(child: Text('${line.extraGuests} extra guests')),
                    Text(formatInr(line.extraGuestAmount)),
                  ],
                ),
              ),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Cleaning fee')),
              Text(formatInr(quote.cleaningFee)),
            ],
          ),
          if (quote.taxAmount > 0) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              key: const Key('tax-row'),
              children: [
                Expanded(
                  child: Text(
                    'Tax (${formatPct(quote.taxPct)}%)',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
                Text(formatInr(quote.taxAmount)),
              ],
            ),
          ],
          if (quote.coupon != null) ...[
            const SizedBox(height: Spacing.xs),
            Row(
              key: const Key('coupon-discount-row'),
              children: [
                Expanded(
                  child: Text(
                    'Coupon (${quote.coupon!.code})',
                    style: TextStyle(color: scheme.primary),
                  ),
                ),
                Text(
                  '-${formatInr(quote.coupon!.discount)}',
                  style: TextStyle(color: scheme.primary),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              Expanded(child: Text('Total', style: textTheme.titleLarge)),
              Text(
                formatInr(quote.total),
                style: textTheme.titleLarge?.copyWith(color: scheme.primary),
              ),
            ],
          ),
          if (widget.advancePct < 100) ...[
            const SizedBox(height: Spacing.md),
            // Material, not a decorated Container: RadioListTile paints its
            // ink on the nearest Material, which a coloured box would hide.
            Material(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
                      child: Text('Payment Option', style: textTheme.labelLarge),
                    ),
                    const SizedBox(height: Spacing.xs),
                    RadioGroup<bool>(
                      groupValue: _splitPayment,
                      onChanged: (val) =>
                          setState(() => _splitPayment = val ?? false),
                      child: Column(
                        children: [
                          RadioListTile<bool>(
                            key: const Key('pay-split-radio'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              'Pay $pctLabel% advance now (${formatInr(advanceAmount)})',
                            ),
                            subtitle: Text(
                                'Remaining ${formatInr(dueAmount)} due at check-in'),
                            value: true,
                          ),
                          RadioListTile<bool>(
                            key: const Key('pay-full-radio'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(
                              'Pay full amount now (${formatInr(quote.total)})',
                            ),
                            value: false,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          FilledButton(
            key: const Key('pay-button'),
            onPressed: widget.busy
                ? null
                : () {
                    if (widget.onPaySplit != null) {
                      final amountToPay =
                          _splitPayment ? advanceAmount : quote.total;
                      widget.onPaySplit!(amountToPay, _splitPayment);
                    } else {
                      widget.onPay();
                    }
                  },
            child: Text(widget.busy
                ? 'Processing…'
                : _splitPayment
                    ? 'Pay advance (${formatInr(advanceAmount)}) & confirm'
                    : 'Pay and confirm'),
          ),
        ],
      ),
      ),
    );
  }

  void _apply() {
    // Codes are stored upper-case (0051's coupons_code_upper) and
    // resolve_coupon compares exactly; textCapitalization does nothing on
    // a desktop keyboard, so normalise here.
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) return;
    unawaited(widget.onApplyCoupon(code));
  }
}

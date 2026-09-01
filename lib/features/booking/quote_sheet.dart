import 'dart:async';

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
  });

  final Quote quote;
  final VoidCallback onPay;
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

    return Padding(
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
          const SizedBox(height: Spacing.lg),
          FilledButton(
            key: const Key('pay-button'),
            onPressed: widget.busy ? null : widget.onPay,
            child: Text(widget.busy ? 'Processing…' : 'Pay and confirm'),
          ),
        ],
      ),
    );
  }

  void _apply() {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    unawaited(widget.onApplyCoupon(code));
  }
}

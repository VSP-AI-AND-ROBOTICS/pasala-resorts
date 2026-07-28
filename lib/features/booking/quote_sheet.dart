import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/models/quote.dart';

/// Displays a server-computed quote. This widget performs no arithmetic:
/// every figure shown comes straight from [Quote].
class QuoteSheet extends StatelessWidget {
  const QuoteSheet({
    super.key,
    required this.quote,
    required this.onPay,
    required this.busy,
  });

  final Quote quote;
  final VoidCallback onPay;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Price breakdown',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final line in quote.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(
                    width: 96,
                    child: Text(formatDay(line.date),
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Expanded(child: Text(line.label)),
                  Text(formatInr(line.amount)),
                ]),
              ),
            for (final line in quote.lines)
              if (line.extraGuests > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(
                      width: 96,
                      child: Text(formatDay(line.date),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(
                        child: Text('${line.extraGuests} extra guests')),
                    Text(formatInr(line.extraGuestAmount)),
                  ]),
                ),
            const Divider(),
            Row(children: [
              const Expanded(child: Text('Cleaning fee')),
              Text(formatInr(quote.cleaningFee)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text('Total',
                      style: Theme.of(context).textTheme.titleLarge)),
              Text(formatInr(quote.total),
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('pay-button'),
              onPressed: busy ? null : onPay,
              child: Text(busy ? 'Processing…' : 'Pay and confirm'),
            ),
          ],
        ),
      );
}

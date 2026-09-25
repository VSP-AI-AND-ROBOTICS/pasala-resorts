import 'package:flutter/material.dart';

import '../finance/finance_tables.dart' show formatMoney;

/// "Includes tax ₹25.00" under a tax-inclusive bill line (food, activities):
/// the amount above it already contains this tax, stored on each order and
/// booking when it was made (`0053_food_spa_tax.sql`). Paise are kept,
/// unlike the whole-rupee `formatInr` lines around it, because tax is
/// rarely a round figure.
class IncludedTaxLine extends StatelessWidget {
  const IncludedTaxLine({super.key, required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'Includes tax ${formatMoney(amount)}',
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

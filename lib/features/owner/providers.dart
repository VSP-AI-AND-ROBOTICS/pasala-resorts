import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/expense.dart';
import '../../data/models/food_sale.dart';
import '../../data/repositories/report_repository.dart';

typedef FoodSalesReportFilter = ({DateTime from, DateTime to, String propertyId});
typedef ExpensesReportFilter = ({DateTime from, DateTime to, String propertyId});

final foodSalesReportProvider =
    FutureProvider.family<List<FoodSalesReportRow>, FoodSalesReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .foodSales(filter.from, filter.to, filter.propertyId),
);

final expensesReportProvider =
    FutureProvider.family<List<ExpensesReportRow>, ExpensesReportFilter>(
  (ref, filter) => ref
      .watch(reportRepositoryProvider)
      .expenses(filter.from, filter.to, filter.propertyId),
);

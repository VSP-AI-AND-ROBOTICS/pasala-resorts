import 'package:flutter/foundation.dart';

@immutable
class DashboardReport {
  final double todayRevenue;
  final double monthRevenue;
  final double monthExpenses;
  final double netProfit;
  final double occupancyRate;
  final int upcomingArrivals;
  final int cancellationsCount;
  final int activeHolds;
  final double foodSalesRevenue;
  final double activitySalesRevenue;

  const DashboardReport({
    required this.todayRevenue,
    required this.monthRevenue,
    required this.monthExpenses,
    required this.netProfit,
    required this.occupancyRate,
    required this.upcomingArrivals,
    required this.cancellationsCount,
    required this.activeHolds,
    required this.foodSalesRevenue,
    required this.activitySalesRevenue,
  });

  factory DashboardReport.fromJson(Map<String, dynamic> json) {
    return DashboardReport(
      todayRevenue: (json['today_revenue'] as num?)?.toDouble() ?? 0.0,
      monthRevenue: (json['month_revenue'] as num?)?.toDouble() ?? 0.0,
      monthExpenses: (json['month_expenses'] as num?)?.toDouble() ?? 0.0,
      netProfit: (json['net_profit'] as num?)?.toDouble() ?? 0.0,
      occupancyRate: (json['occupancy_rate'] as num?)?.toDouble() ?? 0.0,
      upcomingArrivals: json['upcoming_arrivals'] as int? ?? 0,
      cancellationsCount: json['cancellations_count'] as int? ?? 0,
      activeHolds: json['active_holds'] as int? ?? 0,
      foodSalesRevenue: (json['food_sales_revenue'] as num?)?.toDouble() ?? 0.0,
      activitySalesRevenue: (json['activity_sales_revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

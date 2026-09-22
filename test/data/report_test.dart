import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/report.dart';

void main() {
  test('parses the dashboard payload', () {
    final summary = DashboardSummary.fromJson(const {
      'today_revenue': 11500.00,
      'month_revenue': 234500.00,
      'occupancy_pct': 62.5,
      'upcoming_arrivals': 3,
      'cancellations_this_month': 1,
      'active_holds': 2,
    });

    expect(summary.todayRevenue, 11500.00);
    expect(summary.occupancyPct, 62.5);
    expect(summary.upcomingArrivals, 3);
  });

  test('treats a null money figure as zero, never as a crash', () {
    final summary = DashboardSummary.fromJson(const {
      'today_revenue': null,
      'month_revenue': 0,
      'occupancy_pct': 0,
      'upcoming_arrivals': 0,
      'cancellations_this_month': 0,
      'active_holds': 0,
    });

    expect(summary.todayRevenue, 0);
  });
}

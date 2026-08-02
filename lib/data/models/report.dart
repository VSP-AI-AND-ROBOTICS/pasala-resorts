/// The staff dashboard's headline numbers, from `dashboard_summary()`.
/// Every figure is computed server-side -- this class only parses, it never
/// adds, subtracts, or divides. A `null` money figure (a period with no
/// activity yet) is treated as zero rather than left null, because an empty
/// period is normal and must never crash `formatInr`.
class DashboardSummary {
  const DashboardSummary({
    required this.todayRevenue,
    required this.monthRevenue,
    required this.occupancyPct,
    required this.upcomingArrivals,
    required this.cancellationsThisMonth,
    required this.activeHolds,
  });

  final num todayRevenue;
  final num monthRevenue;
  final num occupancyPct;
  final int upcomingArrivals;
  final int cancellationsThisMonth;
  final int activeHolds;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) =>
      DashboardSummary(
        todayRevenue: (json['today_revenue'] as num?) ?? 0,
        monthRevenue: (json['month_revenue'] as num?) ?? 0,
        occupancyPct: (json['occupancy_pct'] as num?) ?? 0,
        upcomingArrivals: (json['upcoming_arrivals'] as num?)?.toInt() ?? 0,
        cancellationsThisMonth:
            (json['cancellations_this_month'] as num?)?.toInt() ?? 0,
        activeHolds: (json['active_holds'] as num?)?.toInt() ?? 0,
      );
}

/// One row of `report_revenue(from, to, property_id)`: a single property's
/// activity on a single day.
class RevenueRow {
  const RevenueRow({
    required this.day,
    required this.propertyId,
    required this.bookings,
    required this.gross,
    required this.refunded,
    required this.net,
  });

  final DateTime day;
  final String propertyId;
  final int bookings;
  final num gross;
  final num refunded;
  final num net;

  factory RevenueRow.fromJson(Map<String, dynamic> json) => RevenueRow(
        day: DateTime.parse(json['day'] as String),
        propertyId: json['property_id'] as String,
        bookings: (json['bookings'] as num?)?.toInt() ?? 0,
        gross: (json['gross'] as num?) ?? 0,
        refunded: (json['refunded'] as num?) ?? 0,
        net: (json['net'] as num?) ?? 0,
      );
}

/// One row of `report_occupancy(from, to, property_id)`: a single unit's
/// occupancy over the requested window.
class OccupancyRow {
  const OccupancyRow({
    required this.unitId,
    required this.unitName,
    required this.nightsAvailable,
    required this.nightsBooked,
    required this.occupancyPct,
  });

  final String unitId;
  final String unitName;
  final int nightsAvailable;
  final int nightsBooked;
  final num occupancyPct;

  factory OccupancyRow.fromJson(Map<String, dynamic> json) => OccupancyRow(
        unitId: json['unit_id'] as String,
        unitName: json['unit_name'] as String,
        nightsAvailable: (json['nights_available'] as num?)?.toInt() ?? 0,
        nightsBooked: (json['nights_booked'] as num?)?.toInt() ?? 0,
        occupancyPct: (json['occupancy_pct'] as num?) ?? 0,
      );
}

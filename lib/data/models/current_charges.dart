/// The live running bill for a stay, from the `current_charges` RPC --
/// computed fresh server-side on every call, never stored client-side
/// beyond the lifetime of one screen.
class CurrentCharges {
  const CurrentCharges({
    required this.stayAmount,
    required this.foodAmount,
    required this.activityAmount,
    required this.total,
    required this.paid,
    required this.balance,
    this.foodTax = 0,
    this.activityTax = 0,
  });

  final double stayAmount;
  final double foodAmount;
  final double activityAmount;
  final double total;
  final double paid;
  final double balance;

  /// The tax already inside [foodAmount] / [activityAmount]
  /// (`0053_food_spa_tax.sql`): each order and booking stores the tax of
  /// the rate it was made at. Not added to [total] -- it is part of it.
  /// 0 from a server without the keys.
  final double foodTax;
  final double activityTax;

  factory CurrentCharges.fromJson(Map<String, dynamic> json) => CurrentCharges(
        stayAmount: (json['stay_amount'] as num).toDouble(),
        foodAmount: (json['food_amount'] as num).toDouble(),
        activityAmount: (json['activity_amount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        paid: (json['paid'] as num).toDouble(),
        balance: (json['balance'] as num).toDouble(),
        foodTax: (json['food_tax'] as num?)?.toDouble() ?? 0,
        activityTax: (json['activity_tax'] as num?)?.toDouble() ?? 0,
      );
}

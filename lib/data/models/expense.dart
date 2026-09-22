/// One row of `expenses`. `category`/`paymentMethod` are free text (not an
/// enum) -- expense categories are business-decided and open-ended (rent,
/// utilities, salaries, maintenance, ...), unlike the closed two-value
/// `SaleCategory`.
class Expense {
  const Expense({
    required this.id,
    required this.propertyId,
    required this.expenseDate,
    required this.category,
    required this.description,
    required this.amount,
    this.paidTo,
    this.paymentMethod,
  });

  final String id;
  final String propertyId;
  final DateTime expenseDate;
  final String category;
  final String description;
  final num amount;
  final String? paidTo;
  final String? paymentMethod;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        expenseDate: DateTime.parse(json['expense_date'] as String),
        category: json['category'] as String,
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num?) ?? 0,
        paidTo: json['paid_to'] as String?,
        paymentMethod: json['payment_method'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'property_id': propertyId,
        'expense_date': expenseDate.toIso8601String().substring(0, 10),
        'category': category,
        'description': description,
        'amount': amount,
        'paid_to': paidTo,
        'payment_method': paymentMethod,
      };
}

/// One row of `report_expenses(from, to, property_id)`.
class ExpensesReportRow {
  const ExpensesReportRow({
    required this.day,
    required this.category,
    required this.total,
  });

  final DateTime day;
  final String category;
  final num total;

  factory ExpensesReportRow.fromJson(Map<String, dynamic> json) =>
      ExpensesReportRow(
        day: DateTime.parse(json['day'] as String),
        category: json['category'] as String,
        total: (json['total'] as num?) ?? 0,
      );
}

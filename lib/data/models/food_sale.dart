import 'payment_method.dart';

enum SaleCategory { food, activity }

SaleCategory saleCategoryFromDb(String raw) => switch (raw) {
      'food' => SaleCategory.food,
      'activity' => SaleCategory.activity,
      _ => throw ArgumentError('unknown sale category $raw'),
    };

String saleCategoryToDb(SaleCategory category) => switch (category) {
      SaleCategory.food => 'food',
      SaleCategory.activity => 'activity',
    };

/// One row of `food_activity_sales` -- a single sale logged by front-desk
/// staff. Named `FoodSale`, not `Sale`, to leave room for a distinct model
/// if some other kind of sale is ever tracked.
class FoodSale {
  const FoodSale({
    required this.id,
    required this.propertyId,
    required this.saleDate,
    required this.category,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.amount,
    this.paymentMethod = PaymentMethod.cash,
    this.notes,
  });

  final String id;
  final String propertyId;
  final DateTime saleDate;
  final SaleCategory category;
  final String itemName;
  final int quantity;
  final num unitPrice;
  final num amount;
  /// How the guest paid at the desk. Never [PaymentMethod.gateway]:
  /// `food_activity_sales_not_gateway` (0048) refuses it, and the form
  /// offers [PaymentMethod.desk] only.
  final PaymentMethod paymentMethod;
  final String? notes;

  factory FoodSale.fromJson(Map<String, dynamic> json) => FoodSale(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        saleDate: DateTime.parse(json['sale_date'] as String),
        category: saleCategoryFromDb(json['category'] as String),
        itemName: json['item_name'] as String,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unit_price'] as num?) ?? 0,
        amount: (json['amount'] as num?) ?? 0,
        paymentMethod: PaymentMethod.fromWire(json['payment_method'] as String?),
        notes: json['notes'] as String?,
      );

  /// Payload for a new/edited sale -- excludes `id` (server-assigned) and
  /// `recorded_by`/`created_at` (server-defaulted).
  Map<String, dynamic> toInsert() => {
        'property_id': propertyId,
        'sale_date': saleDate.toIso8601String().substring(0, 10),
        'category': saleCategoryToDb(category),
        'item_name': itemName,
        'quantity': quantity,
        'unit_price': unitPrice,
        'amount': amount,
        'payment_method': paymentMethod.wire,
        'notes': notes,
      };
}

/// One row of `report_food_sales(from, to, property_id)`.
class FoodSalesReportRow {
  const FoodSalesReportRow({
    required this.day,
    required this.category,
    required this.itemsSold,
    required this.gross,
  });

  final DateTime day;
  final SaleCategory category;
  final int itemsSold;
  final num gross;

  factory FoodSalesReportRow.fromJson(Map<String, dynamic> json) =>
      FoodSalesReportRow(
        day: DateTime.parse(json['day'] as String),
        category: saleCategoryFromDb(json['category'] as String),
        itemsSold: (json['items_sold'] as num?)?.toInt() ?? 0,
        gross: (json['gross'] as num?) ?? 0,
      );
}

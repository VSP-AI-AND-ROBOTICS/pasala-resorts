enum FoodOrderStatus { placed, accepted, preparing, ready, delivered, cancelled }

FoodOrderStatus foodOrderStatusFromDb(String raw) => switch (raw) {
      'placed' => FoodOrderStatus.placed,
      'accepted' => FoodOrderStatus.accepted,
      'preparing' => FoodOrderStatus.preparing,
      'ready' => FoodOrderStatus.ready,
      'delivered' => FoodOrderStatus.delivered,
      'cancelled' => FoodOrderStatus.cancelled,
      _ => throw ArgumentError('unknown food order status $raw'),
    };

String foodOrderStatusToDb(FoodOrderStatus status) => switch (status) {
      FoodOrderStatus.placed => 'placed',
      FoodOrderStatus.accepted => 'accepted',
      FoodOrderStatus.preparing => 'preparing',
      FoodOrderStatus.ready => 'ready',
      FoodOrderStatus.delivered => 'delivered',
      FoodOrderStatus.cancelled => 'cancelled',
    };

String foodOrderStatusLabel(FoodOrderStatus status) => switch (status) {
      FoodOrderStatus.placed => 'Placed',
      FoodOrderStatus.accepted => 'Accepted',
      FoodOrderStatus.preparing => 'Preparing',
      FoodOrderStatus.ready => 'Ready',
      FoodOrderStatus.delivered => 'Delivered',
      FoodOrderStatus.cancelled => 'Cancelled',
    };

/// One line of a placed order. [itemName]/[unitPrice] are the server's own
/// snapshot at order time -- never the live [FoodItem] price, which may
/// have since changed.
class FoodOrderItem {
  const FoodOrderItem({
    required this.foodItemId,
    required this.itemName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });

  final String foodItemId;
  final String itemName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  factory FoodOrderItem.fromJson(Map<String, dynamic> json) => FoodOrderItem(
        foodItemId: json['food_item_id'] as String,
        itemName: json['item_name'] as String,
        unitPrice: (json['unit_price'] as num).toDouble(),
        quantity: json['quantity'] as int,
        lineTotal: (json['line_total'] as num).toDouble(),
      );
}

class FoodOrder {
  const FoodOrder({
    required this.id,
    required this.reservationId,
    required this.status,
    required this.total,
    this.notes,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String reservationId;
  final FoodOrderStatus status;
  final double total;
  final String? notes;
  final List<FoodOrderItem> items;
  final DateTime? createdAt;

  factory FoodOrder.fromJson(Map<String, dynamic> json) => FoodOrder(
        id: json['id'] as String,
        reservationId: json['reservation_id'] as String,
        status: foodOrderStatusFromDb(json['status'] as String),
        total: (json['total'] as num).toDouble(),
        notes: json['notes'] as String?,
        items: (json['food_order_items'] as List<dynamic>?)
                ?.map((e) => FoodOrderItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        createdAt: json['created_at'] == null
            ? null
            : DateTime.parse(json['created_at'] as String),
      );
}

/// A menu category (e.g. "Breakfast", "Lunch") -- property-scoped and
/// admin-managed via 0032_food_ordering.sql.
class FoodCategory {
  const FoodCategory({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String propertyId;
  final String name;
  final int sortOrder;

  factory FoodCategory.fromJson(Map<String, dynamic> json) => FoodCategory(
        id: json['id'] as String,
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

/// One orderable menu item. [isAvailable] mirrors the server's own
/// availability gate -- an unavailable item is still shown (so past
/// orders that reference it still render) but cannot be added to a cart.
class FoodItem {
  const FoodItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    required this.isAvailable,
    this.description,
  });

  final String id;
  final String categoryId;
  final String name;
  final String? description;
  final double price;
  final bool isAvailable;

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
        id: json['id'] as String,
        categoryId: json['category_id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        price: (json['price'] as num).toDouble(),
        isAvailable: json['is_available'] as bool? ?? true,
      );
}

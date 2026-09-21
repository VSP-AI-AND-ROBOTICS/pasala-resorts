import 'package:flutter/foundation.dart';

@immutable
class ResortExpense {
  final String id;
  final String resortId;
  final String category; // 'maintenance', 'utilities', 'staff_salary', 'supplies', 'food_inventory'
  final double amount;
  final String description;
  final DateTime expenseDate;
  final DateTime createdAt;

  const ResortExpense({
    required this.id,
    required this.resortId,
    required this.category,
    required this.amount,
    required this.description,
    required this.expenseDate,
    required this.createdAt,
  });

  factory ResortExpense.fromJson(Map<String, dynamic> json) {
    return ResortExpense(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      category: json['category'] as String,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String,
      expenseDate: DateTime.parse(json['expense_date'] as String),
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'category': category,
      'amount': amount,
      'description': description,
      'expense_date': expenseDate.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
    };
  }
}

@immutable
class LedgerSettlement {
  final String id;
  final String resortId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalRevenue;
  final double platformFee;
  final double payoutAmount;
  final String status; // 'draft', 'settled', 'transferred'
  final String transactionRef;
  final DateTime createdAt;

  const LedgerSettlement({
    required this.id,
    required this.resortId,
    required this.periodStart,
    required this.periodEnd,
    required this.totalRevenue,
    required this.platformFee,
    required this.payoutAmount,
    required this.status,
    required this.transactionRef,
    required this.createdAt,
  });

  factory LedgerSettlement.fromJson(Map<String, dynamic> json) {
    return LedgerSettlement(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      totalRevenue: (json['total_revenue'] as num).toDouble(),
      platformFee: (json['platform_fee'] as num).toDouble(),
      payoutAmount: (json['payout_amount'] as num).toDouble(),
      status: json['status'] as String? ?? 'draft',
      transactionRef: json['transaction_ref'] as String? ?? '',
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'period_start': periodStart.toIso8601String().split('T')[0],
      'period_end': periodEnd.toIso8601String().split('T')[0],
      'total_revenue': totalRevenue,
      'platform_fee': platformFee,
      'payout_amount': payoutAmount,
      'status': status,
      'transaction_ref': transactionRef,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

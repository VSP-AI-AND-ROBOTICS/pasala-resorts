import 'package:flutter/foundation.dart';
import 'resort.dart';

@immutable
class InchargeSalaryPayment {
  final String id;
  final String resortId;
  final String inchargeEmail;
  final String inchargeName;
  final double amount;
  final String monthYear; // e.g. "September 2026"
  final String paymentMode; // 'UPI', 'Bank Transfer (NEFT/RTGS)', 'Cash', 'Cheque'
  final String transactionRef;
  final String? notes;
  final DateTime disbursedAt;

  const InchargeSalaryPayment({
    required this.id,
    required this.resortId,
    required this.inchargeEmail,
    required this.inchargeName,
    required this.amount,
    required this.monthYear,
    required this.paymentMode,
    required this.transactionRef,
    this.notes,
    required this.disbursedAt,
  });

  factory InchargeSalaryPayment.fromJson(Map<String, dynamic> json) {
    return InchargeSalaryPayment(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      inchargeEmail: json['incharge_email'] as String,
      inchargeName: json['incharge_name'] as String,
      amount: (json['amount'] as num).toDouble(),
      monthYear: json['month_year'] as String,
      paymentMode: json['payment_mode'] as String,
      transactionRef: json['transaction_ref'] as String,
      notes: json['notes'] as String?,
      disbursedAt: DateTime.parse(json['disbursed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'incharge_email': inchargeEmail,
      'incharge_name': inchargeName,
      'amount': amount,
      'month_year': monthYear,
      'payment_mode': paymentMode,
      'transaction_ref': transactionRef,
      'notes': notes,
      'disbursed_at': disbursedAt.toIso8601String(),
    };
  }
}

@immutable
class StaffSalaryPayment {
  final String id;
  final String resortId;
  final String staffId;
  final String staffName;
  final String roleTitle;
  final double amount;
  final String monthYear;
  final String paymentMode;
  final String status; // 'paid', 'pending'
  final String transactionRef;
  final DateTime paidAt;

  const StaffSalaryPayment({
    required this.id,
    required this.resortId,
    required this.staffId,
    required this.staffName,
    required this.roleTitle,
    required this.amount,
    required this.monthYear,
    required this.paymentMode,
    required this.status,
    required this.transactionRef,
    required this.paidAt,
  });

  factory StaffSalaryPayment.fromJson(Map<String, dynamic> json) {
    return StaffSalaryPayment(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      staffId: json['staff_id'] as String,
      staffName: json['staff_name'] as String,
      roleTitle: json['role_title'] as String,
      amount: (json['amount'] as num).toDouble(),
      monthYear: json['month_year'] as String,
      paymentMode: json['payment_mode'] as String,
      status: json['status'] as String,
      transactionRef: json['transaction_ref'] as String,
      paidAt: DateTime.parse(json['paid_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'staff_id': staffId,
      'staff_name': staffName,
      'role_title': roleTitle,
      'amount': amount,
      'month_year': monthYear,
      'payment_mode': paymentMode,
      'status': status,
      'transaction_ref': transactionRef,
      'paid_at': paidAt.toIso8601String(),
    };
  }
}

enum TierRequestStatus {
  pendingPaymentDetails, // Admin requested change, Super Admin needs to send payment details
  awaitingAdminPayment,  // Super Admin sent payment details, waiting for Admin to pay & provide UTR
  completed,              // Payment submitted & verified, Tier updated
  rejected,
}

@immutable
class TierChangeRequest {
  final String id;
  final String resortId;
  final String resortName;
  final SubscriptionTier currentTier;
  final SubscriptionTier requestedTier;
  final TierRequestStatus status;
  final double amountDue;
  final String? paymentInstructions; // UPI ID / Bank Details provided by Super Admin
  final String? adminPaymentRef;     // UTR / Transaction reference entered by Admin
  final DateTime createdAt;
  final DateTime? updatedAt;

  const TierChangeRequest({
    required this.id,
    required this.resortId,
    required this.resortName,
    required this.currentTier,
    required this.requestedTier,
    required this.status,
    required this.amountDue,
    this.paymentInstructions,
    this.adminPaymentRef,
    required this.createdAt,
    this.updatedAt,
  });

  TierChangeRequest copyWith({
    SubscriptionTier? currentTier,
    SubscriptionTier? requestedTier,
    TierRequestStatus? status,
    double? amountDue,
    String? paymentInstructions,
    String? adminPaymentRef,
    DateTime? updatedAt,
  }) {
    return TierChangeRequest(
      id: id,
      resortId: resortId,
      resortName: resortName,
      currentTier: currentTier ?? this.currentTier,
      requestedTier: requestedTier ?? this.requestedTier,
      status: status ?? this.status,
      amountDue: amountDue ?? this.amountDue,
      paymentInstructions: paymentInstructions ?? this.paymentInstructions,
      adminPaymentRef: adminPaymentRef ?? this.adminPaymentRef,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

enum StaffFundRequestStatus {
  pending,  // Incharge requested staff payroll funds from Admin
  funded,   // Admin approved and transferred funds to Incharge
  rejected,
}

@immutable
class StaffSalaryFundRequest {
  final String id;
  final String resortId;
  final String inchargeEmail;
  final String inchargeName;
  final String monthYear; // e.g. "September 2026"
  final double requestedAmount;
  final int staffCount;
  final String? notes;
  final StaffFundRequestStatus status;
  final double? fundedAmount;
  final String? paymentMode; // 'Bank Transfer / NEFT', 'UPI Transfer', 'Company Cash'
  final String? transactionRef; // UTR or Ref number
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime? fundedAt;

  const StaffSalaryFundRequest({
    required this.id,
    required this.resortId,
    required this.inchargeEmail,
    required this.inchargeName,
    required this.monthYear,
    required this.requestedAmount,
    required this.staffCount,
    this.notes,
    required this.status,
    this.fundedAmount,
    this.paymentMode,
    this.transactionRef,
    this.adminNotes,
    required this.createdAt,
    this.fundedAt,
  });

  StaffSalaryFundRequest copyWith({
    StaffFundRequestStatus? status,
    double? fundedAmount,
    String? paymentMode,
    String? transactionRef,
    String? adminNotes,
    DateTime? fundedAt,
  }) {
    return StaffSalaryFundRequest(
      id: id,
      resortId: resortId,
      inchargeEmail: inchargeEmail,
      inchargeName: inchargeName,
      monthYear: monthYear,
      requestedAmount: requestedAmount,
      staffCount: staffCount,
      notes: notes,
      status: status ?? this.status,
      fundedAmount: fundedAmount ?? this.fundedAmount,
      paymentMode: paymentMode ?? this.paymentMode,
      transactionRef: transactionRef ?? this.transactionRef,
      adminNotes: adminNotes ?? this.adminNotes,
      createdAt: createdAt,
      fundedAt: fundedAt ?? this.fundedAt,
    );
  }

  factory StaffSalaryFundRequest.fromJson(Map<String, dynamic> json) {
    return StaffSalaryFundRequest(
      id: json['id'] as String,
      resortId: json['resort_id'] as String,
      inchargeEmail: json['incharge_email'] as String,
      inchargeName: json['incharge_name'] as String,
      monthYear: json['month_year'] as String,
      requestedAmount: (json['requested_amount'] as num).toDouble(),
      staffCount: json['staff_count'] as int? ?? 1,
      notes: json['notes'] as String?,
      status: StaffFundRequestStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => StaffFundRequestStatus.pending,
      ),
      fundedAmount: (json['funded_amount'] as num?)?.toDouble(),
      paymentMode: json['payment_mode'] as String?,
      transactionRef: json['transaction_ref'] as String?,
      adminNotes: json['admin_notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      fundedAt: json['funded_at'] != null ? DateTime.parse(json['funded_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'resort_id': resortId,
      'incharge_email': inchargeEmail,
      'incharge_name': inchargeName,
      'month_year': monthYear,
      'requested_amount': requestedAmount,
      'staff_count': staffCount,
      'notes': notes,
      'status': status.name,
      'funded_amount': fundedAmount,
      'payment_mode': paymentMode,
      'transaction_ref': transactionRef,
      'admin_notes': adminNotes,
      'created_at': createdAt.toIso8601String(),
      'funded_at': fundedAt?.toIso8601String(),
    };
  }
}

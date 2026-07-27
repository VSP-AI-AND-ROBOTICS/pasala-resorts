class QuoteLine {
  const QuoteLine({
    required this.date,
    required this.label,
    required this.amount,
    required this.extraGuests,
    required this.extraGuestAmount,
  });

  final DateTime date;
  final String label;
  final num amount;
  final int extraGuests;
  final num extraGuestAmount;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        date: DateTime.parse('${json['date']}T00:00:00Z'),
        label: json['label'] as String,
        amount: json['amount'] as num,
        extraGuests: (json['extra_guests'] as num?)?.toInt() ?? 0,
        extraGuestAmount: json['extra_guest_amount'] as num? ?? 0,
      );
}

class Quote {
  const Quote({
    required this.currency,
    required this.guests,
    required this.lines,
    required this.subtotal,
    required this.cleaningFee,
    required this.total,
  });

  final String currency;
  final int guests;
  final List<QuoteLine> lines;
  final num subtotal;
  final num cleaningFee;

  /// Server-computed. Never derived from [lines] — the server is the only
  /// authority on price.
  final num total;

  factory Quote.fromJson(Map<String, dynamic> json) => Quote(
        currency: json['currency'] as String? ?? 'INR',
        guests: (json['guests'] as num).toInt(),
        lines: (json['lines'] as List<dynamic>)
            .map((e) => QuoteLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtotal: json['subtotal'] as num,
        cleaningFee: json['cleaning_fee'] as num,
        total: json['total'] as num,
      );
}

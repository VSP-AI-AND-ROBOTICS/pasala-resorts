import 'package:intl/intl.dart';

import '../format.dart';

final _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

/// `1080` -> `₹1,080.00`: paise kept, like the Finance screen's
/// `formatMoney`, because a document is a record, not a glance.
String pdfMoney(num amount) => _money.format(amount);

/// `12 Aug 2026`, in the device's local time like every date in the app.
String pdfDate(DateTime d) => formatDate(d.toLocal());

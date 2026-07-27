import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _day = DateFormat('EEE, d MMM');

String formatInr(num amount) => _inr.format(amount);
String formatDay(DateTime d) => _day.format(d);

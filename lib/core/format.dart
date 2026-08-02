import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _day = DateFormat('EEE, d MMM');
final _date = DateFormat('d MMM yyyy');

String formatInr(num amount) => _inr.format(amount);
String formatDay(DateTime d) => _day.format(d);

/// A full date including the year -- unlike [formatDay], which drops the
/// year for the customer-facing "which day of the week" reading. Reports
/// can span an arbitrary range chosen by an admin, so the year matters here.
String formatDate(DateTime d) => _date.format(d);

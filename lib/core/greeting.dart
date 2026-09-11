// Shared by every dashboard-style landing screen (`AdminHomeScreen`,
// `OwnerHomeScreen`) so "Good Morning, Asha" and its date line never drift
// between them -- previously each screen kept its own private copy.

const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String greetingFor(DateTime now) {
  if (now.hour < 12) return 'Good Morning';
  if (now.hour < 17) return 'Good Afternoon';
  return 'Good Evening';
}

/// "Wednesday, 2 September 2026" -- the full form these dashboards use,
/// distinct from `formatDay`/`formatDate` in `core/format.dart` (which
/// abbreviate for customer-facing booking dates).
String fullDateFor(DateTime now) =>
    '${weekdayNames[now.weekday - 1]}, ${now.day} ${monthNames[now.month - 1]} ${now.year}';

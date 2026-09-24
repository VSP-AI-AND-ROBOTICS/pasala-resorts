import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/greeting.dart';

void main() {
  group('greetingFor', () {
    test('morning hours (before 12) -> Good Morning', () {
      expect(greetingFor(DateTime(2026, 1, 1, 5, 0)), 'Good Morning');
      expect(greetingFor(DateTime(2026, 1, 1, 11, 59)), 'Good Morning');
    });

    test('afternoon hours (12-16) -> Good Afternoon', () {
      expect(greetingFor(DateTime(2026, 1, 1, 12, 0)), 'Good Afternoon');
      expect(greetingFor(DateTime(2026, 1, 1, 16, 59)), 'Good Afternoon');
    });

    test('evening/night hours (17+) -> Good Evening', () {
      expect(greetingFor(DateTime(2026, 1, 1, 17, 0)), 'Good Evening');
      expect(greetingFor(DateTime(2026, 1, 1, 23, 0)), 'Good Evening');
    });
  });

  // `greetingLine` is new for the guest browse hero: it wraps the existing
  // `greetingFor` (shared with the owner/admin dashboards) with the
  // signed-in user's first name, or a bare "Welcome" for a signed-out or
  // nameless guest -- see `_BrowseHero` in browse_screen.dart.
  group('greetingLine', () {
    test('combines the time-of-day greeting with the first name', () {
      expect(
        greetingLine(DateTime(2026, 1, 1, 19, 0), 'Ravi Kumar'),
        'Good Evening, Ravi',
      );
      expect(
        greetingLine(DateTime(2026, 1, 1, 8, 0), 'Ananya'),
        'Good Morning, Ananya',
      );
    });

    test('signed out (null name) -> Welcome', () {
      expect(greetingLine(DateTime(2026, 1, 1, 19, 0), null), 'Welcome');
    });

    test('signed in with a blank/whitespace-only name -> Welcome', () {
      expect(greetingLine(DateTime(2026, 1, 1, 19, 0), '   '), 'Welcome');
    });

    test('collapses extra whitespace before taking the first word', () {
      expect(
        greetingLine(DateTime(2026, 1, 1, 8, 0), '  Ravi   Kumar '),
        'Good Morning, Ravi',
      );
    });
  });
}

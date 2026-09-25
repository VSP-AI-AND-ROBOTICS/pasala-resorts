import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/ical_repository.dart';

void main() {
  const token = '0123456789abcdef0123456789abcdef0123456789abcdef';

  test('points at the ical-export Edge Function with the token as a .ics '
      'file', () {
    expect(
      icalExportUrl('https://abc.supabase.co', token),
      'https://abc.supabase.co/functions/v1/ical-export/$token.ics',
    );
  });

  test('a trailing slash on the project URL does not double up', () {
    expect(
      icalExportUrl('http://127.0.0.1:54321/', token),
      'http://127.0.0.1:54321/functions/v1/ical-export/$token.ics',
    );
  });

  test('carries no API key -- the OTA fetches a plain link', () {
    final url = icalExportUrl('https://abc.supabase.co', token);
    expect(url, isNot(contains('apikey')));
    expect(url, isNot(contains('rest/v1')));
  });
}

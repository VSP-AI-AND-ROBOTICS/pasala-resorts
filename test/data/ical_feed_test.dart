import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';

void main() {
  test('parses a feed that has never synced', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f1',
      'unit_id': 'u1',
      'url': 'https://www.airbnb.com/calendar/ical/1.ics',
      'label': 'Airbnb',
      'is_active': true,
      'last_synced_at': null,
      'last_error': null,
    });

    expect(feed.label, 'Airbnb');
    expect(feed.lastSyncedAt, isNull);
    expect(feed.lastError, isNull);
  });

  test('parses a feed with a recorded last error -- shown honestly, not '
      'hidden', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f2',
      'unit_id': 'u1',
      'url': 'https://www.booking.com/ical/1.ics',
      'label': null,
      'is_active': true,
      'last_synced_at': '2026-08-01T10:00:00Z',
      'last_error': 'HTTP 503',
    });

    expect(feed.label, isNull);
    expect(feed.lastSyncedAt, isNotNull);
    expect(feed.lastError, 'HTTP 503');
  });

  test('is_active defaults to true when the server omits it', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f3',
      'unit_id': 'u1',
      'url': 'https://example.com/1.ics',
      'label': null,
      'last_synced_at': null,
      'last_error': null,
    });

    expect(feed.isActive, isTrue);
  });

  test('IcalSyncResult parses every status the RPC can return', () {
    expect(
      IcalSyncResult.fromJson(const {'status': 'requested'}).status,
      'requested',
    );
    expect(
      IcalSyncResult.fromJson(const {'status': 'pending'}).status,
      'pending',
    );
    final ok = IcalSyncResult.fromJson(const {
      'status': 'ok',
      'created': 1,
      'updated': 0,
      'unchanged': 2,
      'conflicts': 1,
    });
    expect(ok.status, 'ok');
    expect(ok.conflicts, 1);
    final error = IcalSyncResult.fromJson(const {
      'status': 'error',
      'error': 'HTTP 503',
    });
    expect(error.status, 'error');
    expect(error.error, 'HTTP 503');
  });
}

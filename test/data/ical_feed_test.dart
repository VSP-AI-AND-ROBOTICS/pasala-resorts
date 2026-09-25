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

  test('parses the sync status columns added in 0058', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f4',
      'unit_id': 'u1',
      'url': 'https://www.airbnb.com/calendar/ical/1.ics',
      'label': 'Airbnb',
      'is_active': true,
      'last_synced_at': '2027-01-01T11:55:00Z',
      'last_error': null,
      'last_status': 'ok',
      'last_event_count': 3,
      'last_ok_at': '2027-01-01T11:55:00+00:00',
    });

    expect(feed.lastStatus, FeedSyncStatus.ok);
    expect(feed.lastEventCount, 3);
    expect(feed.lastOkAt, DateTime.utc(2027, 1, 1, 11, 55));
  });

  test('a feed that never synced has no status, count or last good sync', () {
    final feed = IcalFeed.fromJson(const {
      'id': 'f5',
      'unit_id': 'u1',
      'url': 'https://example.com/1.ics',
      'label': null,
      'last_synced_at': null,
      'last_error': null,
      'last_status': null,
      'last_event_count': null,
      'last_ok_at': null,
    });

    expect(feed.lastStatus, isNull);
    expect(feed.lastEventCount, isNull);
    expect(feed.lastOkAt, isNull);
  });

  test('feedSyncStatusFromDb reads ok and error, and nothing else', () {
    expect(feedSyncStatusFromDb('ok'), FeedSyncStatus.ok);
    expect(feedSyncStatusFromDb('error'), FeedSyncStatus.error);
    expect(feedSyncStatusFromDb('pending'), isNull);
    expect(feedSyncStatusFromDb(null), isNull);
  });

  test('IcalSyncResult reads every count ical_poll_feed returns', () {
    final ok = IcalSyncResult.fromJson(const {
      'status': 'ok',
      'events': 4,
      'created': 2,
      'updated': 0,
      'unchanged': 0,
      'conflicts': 1,
      'echoes': 1,
      'failed': 0,
    });

    expect(ok.events, 4);
    expect(ok.created, 2);
    expect(ok.updated, 0);
    expect(ok.unchanged, 0);
    expect(ok.conflicts, 1);
    expect(ok.echoes, 1);
    expect(ok.failed, 0);
  });

  test('isFinal is true only once a response was collected', () {
    expect(const IcalSyncResult(status: 'ok').isFinal, isTrue);
    expect(const IcalSyncResult(status: 'error').isFinal, isTrue);
    expect(const IcalSyncResult(status: 'requested').isFinal, isFalse);
    expect(const IcalSyncResult(status: 'pending').isFinal, isFalse);
  });
}

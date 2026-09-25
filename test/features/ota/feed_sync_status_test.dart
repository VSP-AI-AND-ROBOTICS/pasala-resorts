import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/ical_feed.dart';
import 'package:pasala/data/repositories/ical_repository.dart';
import 'package:pasala/features/ota/feed_sync_status.dart';

import '../../support/fake_ical_source.dart';

void main() {
  final now = DateTime.utc(2027, 1, 10, 12, 0);

  group('syncAgo', () {
    test('under a minute, or in the future, is just now', () {
      expect(syncAgo(now, now), 'just now');
      expect(syncAgo(now.subtract(const Duration(seconds: 59)), now), 'just now');
      expect(syncAgo(now.add(const Duration(minutes: 3)), now), 'just now');
    });

    test('minutes, hours, then days', () {
      expect(syncAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
      expect(syncAgo(now.subtract(const Duration(minutes: 59)), now), '59 min ago');
      expect(syncAgo(now.subtract(const Duration(minutes: 60)), now), '1 h ago');
      expect(syncAgo(now.subtract(const Duration(hours: 23)), now), '23 h ago');
      expect(syncAgo(now.subtract(const Duration(hours: 24)), now), '1 day ago');
      expect(syncAgo(now.subtract(const Duration(days: 2)), now), '2 days ago');
    });
  });

  test('eventCount is singular for one', () {
    expect(eventCount(0), '0 events');
    expect(eventCount(1), '1 event');
    expect(eventCount(3), '3 events');
  });

  test('feedErrorHint', () {
    expect(feedErrorHint('HTTP 404'), hintRelink);
    expect(feedErrorHint('HTTP 410'), hintRelink);
    expect(feedErrorHint('HTTP 403'), hintRelink);
    expect(feedErrorHint('HTTP 503'), isNull);
    expect(feedErrorHint('not a calendar: the link did not return iCal data'),
        hintNotCalendar);
    expect(feedErrorHint('request timed out'), isNull);
    expect(feedErrorHint(null), isNull);
  });

  group('feedStatusLines', () {
    test('never synced', () {
      expect(feedStatusLines(icalFeed(), now),
          [const FeedLine('Never synced', FeedLineTone.neutral)]);
    });

    test('ok: when and how many events', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 3,
      );
      expect(feedStatusLines(feed, now),
          [const FeedLine('Last sync 5 min ago · 3 events', FeedLineTone.neutral)]);
    });

    test('ok with skipped events: the note is a warning', () {
      const note = '1 event(s) conflicted with an existing booking and were skipped';
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 1,
        lastError: note,
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Last sync 5 min ago · 1 event', FeedLineTone.neutral),
        const FeedLine(note, FeedLineTone.warning),
      ]);
    });

    test('error: what failed, what to do, and the last good sync', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 5)),
        lastStatus: FeedSyncStatus.error,
        lastError: 'HTTP 404',
        lastOkAt: now.subtract(const Duration(days: 2)),
        lastEventCount: 3,
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Sync failed 5 min ago: HTTP 404', FeedLineTone.error),
        const FeedLine(hintRelink, FeedLineTone.error),
        const FeedLine('Last good sync 2 days ago', FeedLineTone.neutral),
      ]);
    });

    test('error on a feed that never worked', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 1)),
        lastStatus: FeedSyncStatus.error,
        lastError: 'request timed out',
      );
      expect(feedStatusLines(feed, now), [
        const FeedLine('Sync failed 1 min ago: request timed out', FeedLineTone.error),
        const FeedLine('No successful sync yet', FeedLineTone.neutral),
      ]);
    });

    test('a status the app does not know reads as ok, without a count', () {
      final feed = icalFeed(lastSyncedAt: now.subtract(const Duration(minutes: 2)));
      expect(feedStatusLines(feed, now),
          [const FeedLine('Last sync 2 min ago', FeedLineTone.neutral)]);
    });

    test('an active feed not synced for over an hour is stale', () {
      final feed = icalFeed(
        lastSyncedAt: now.subtract(const Duration(minutes: 61)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      expect(feedStatusLines(feed, now).last,
          const FeedLine(staleWarning, FeedLineTone.warning));
    });

    test('an hour exactly is not stale yet, and an inactive feed never is', () {
      final onTheHour = icalFeed(
        lastSyncedAt: now.subtract(const Duration(hours: 1)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      final paused = icalFeed(
        isActive: false,
        lastSyncedAt: now.subtract(const Duration(days: 3)),
        lastStatus: FeedSyncStatus.ok,
        lastEventCount: 2,
      );
      expect(feedStatusLines(onTheHour, now), hasLength(1));
      expect(feedStatusLines(paused, now), hasLength(1));
    });
  });

  group('syncOutcomeMessage', () {
    test('ok', () {
      expect(syncOutcomeMessage(const IcalSyncResult(status: 'ok', events: 3)),
          'Synced -- 3 events');
    });

    test('ok with conflicts and unreadable events', () {
      expect(
        syncOutcomeMessage(const IcalSyncResult(
            status: 'ok', events: 4, conflicts: 1, failed: 2)),
        'Synced -- 4 events, 1 conflict skipped, 2 unreadable events skipped',
      );
    });

    test('echoes are not mentioned -- they are not a problem', () {
      expect(
        syncOutcomeMessage(
            const IcalSyncResult(status: 'ok', events: 2, echoes: 2)),
        'Synced -- 2 events',
      );
    });

    test('error', () {
      expect(
        syncOutcomeMessage(
            const IcalSyncResult(status: 'error', error: 'HTTP 503')),
        'Sync failed: HTTP 503',
      );
    });

    test('still running', () {
      expect(syncOutcomeMessage(const IcalSyncResult(status: 'pending')),
          'Still syncing -- the result will show here shortly.');
    });
  });
}

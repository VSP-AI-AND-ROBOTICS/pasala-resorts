import '../../data/models/ical_feed.dart';
import '../../data/repositories/ical_repository.dart';

/// How a status line under an import feed reads: plain, a warning (amber,
/// with a warning icon) or an error (red, with an error icon).
enum FeedLineTone { neutral, warning, error }

class FeedLine {
  const FeedLine(this.text, this.tone);
  final String text;
  final FeedLineTone tone;

  @override
  bool operator ==(Object other) =>
      other is FeedLine && other.text == text && other.tone == tone;

  @override
  int get hashCode => Object.hash(text, tone);

  @override
  String toString() => 'FeedLine($text, $tone)';
}

/// An active feed whose last sync is older than this has missed several
/// 15-minute runs.
const staleAfter = Duration(hours: 1);

const hintRelink =
    'The OTA no longer serves this link. Copy the export link from the OTA '
    'again and replace this feed.';
const hintNotCalendar =
    'Check that you pasted the calendar export link, not the listing page.';
const staleWarning =
    'Automatic sync has not run for over an hour. Press Sync now.';

/// `just now`, `5 min ago`, `3 h ago`, `2 days ago`. A time slightly in the
/// future (the phone's clock behind the server's) reads as `just now`.
String syncAgo(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}

/// `1 event`, `3 events`.
String eventCount(int n) => n == 1 ? '1 event' : '$n events';

/// What the admin can do about a feed-level [error], or null.
String? feedErrorHint(String? error) {
  if (error == null) return null;
  if (RegExp(r'^HTTP (401|403|404|410)\b').hasMatch(error)) return hintRelink;
  if (error.startsWith('not a calendar')) return hintNotCalendar;
  return null;
}

/// The status lines under one import feed, most important first.
List<FeedLine> feedStatusLines(IcalFeed feed, DateTime now) {
  final syncedAt = feed.lastSyncedAt;
  if (syncedAt == null) {
    return const [FeedLine('Never synced', FeedLineTone.neutral)];
  }

  final ago = syncAgo(syncedAt, now);
  final lines = <FeedLine>[];
  if (feed.lastStatus == FeedSyncStatus.error) {
    lines.add(FeedLine(
      'Sync failed $ago: ${feed.lastError ?? 'unknown error'}',
      FeedLineTone.error,
    ));
    final hint = feedErrorHint(feed.lastError);
    if (hint != null) lines.add(FeedLine(hint, FeedLineTone.error));
    final okAt = feed.lastOkAt;
    lines.add(FeedLine(
      okAt == null
          ? 'No successful sync yet'
          : 'Last good sync ${syncAgo(okAt, now)}',
      FeedLineTone.neutral,
    ));
  } else {
    final count = feed.lastEventCount;
    lines.add(FeedLine(
      count == null ? 'Last sync $ago' : 'Last sync $ago · ${eventCount(count)}',
      FeedLineTone.neutral,
    ));
    final note = feed.lastError;
    if (note != null) lines.add(FeedLine(note, FeedLineTone.warning));
  }

  if (feed.isActive && now.difference(syncedAt) > staleAfter) {
    lines.add(const FeedLine(staleWarning, FeedLineTone.warning));
  }
  return lines;
}

/// The snackbar after "Sync now".
String syncOutcomeMessage(IcalSyncResult result) => switch (result.status) {
      'ok' => _okMessage(result),
      'error' => 'Sync failed: ${result.error ?? 'unknown error'}',
      _ => 'Still syncing -- the result will show here shortly.',
    };

String _okMessage(IcalSyncResult result) {
  final parts = ['Synced -- ${eventCount(result.events ?? 0)}'];
  final conflicts = result.conflicts ?? 0;
  if (conflicts > 0) {
    parts.add('$conflicts conflict${conflicts == 1 ? '' : 's'} skipped');
  }
  final failed = result.failed ?? 0;
  if (failed > 0) {
    parts.add('$failed unreadable event${failed == 1 ? '' : 's'} skipped');
  }
  return parts.join(', ');
}

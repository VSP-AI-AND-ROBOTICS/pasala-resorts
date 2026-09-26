import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/ical_feed.dart';
import '../../data/repositories/ical_repository.dart';
import '../../data/repositories/ical_sync_runner.dart';
import 'feed_sync_status.dart';

/// The amber used for warnings, the same as the room grid's Cleaning.
const _warningColor = Color(0xFFB26A00);

/// `http://`, `https://` or `webcal://` followed by something -- the form's
/// first check; the `ical_feeds` trigger (P0039) is the real rule.
final _feedUrlPattern =
    RegExp(r'^(https?|webcal)://\S+$', caseSensitive: false);

/// Every `ical_feeds` row for one unit -- RLS (`ical_feeds_read`) scopes
/// this to the resort's owners and admins; anyone else gets zero rows, not
/// an error, same convention as every other admin-only list in this app.
final icalFeedsProvider = FutureProvider.family<List<IcalFeed>, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).feeds(unitId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

/// The unit's current export token, from `ical_export_tokens` (also
/// admin-only -- see `ical_repository.dart`'s header for why it is not a
/// column on `units`).
final icalExportTokenProvider = FutureProvider.family<String, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).exportToken(unitId),
  // Screens show their own Retry button; don't also auto-retry (Riverpod 3
  // retries non-Error throws by default).
  retry: (retryCount, error) => null,
);

/// `/admin/ota/:unitId` -- Airbnb/Booking.com calendar sync for one unit,
/// with no paid channel manager: an export URL to paste INTO the OTA
/// (top), and the list of feeds this unit imports FROM the OTA, with add,
/// remove and a manual Sync (below). Reachable only by an admin --
/// `ical_feeds_admin`/`ical_export_tokens_admin` RLS is the real
/// enforcement underneath, same as everywhere else in `/admin/*`.
class IcalScreen extends StatelessWidget {
  const IcalScreen({
    super.key,
    required this.unitId,
    this.clock = DateTime.now,
  });

  final String unitId;

  /// What "5 min ago" is measured against; injectable so tests do not
  /// depend on the wall clock.
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OTA calendar sync')),
        body: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _ExportSection(unitId: unitId),
            const SectionHeader(title: 'Import feeds'),
            _ImportFeedsSection(unitId: unitId, clock: clock),
          ],
        ),
      );
}

class _ExportSection extends ConsumerWidget {
  const _ExportSection({required this.unitId});
  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenAsync = ref.watch(icalExportTokenProvider(unitId));
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export URL', style: textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              'Paste this link into the OTA\'s "import calendar" setting '
              '(Airbnb: Availability -> Connect calendars; Booking.com: '
              'Rates & Availability -> Sync calendars). It lists only busy '
              'dates -- no guest name, email or amount ever appears in it.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: Spacing.sm),
            AsyncView(
              value: tokenAsync,
              onRetry: () => ref.invalidate(icalExportTokenProvider(unitId)),
              data: (token) => _ExportUrlRow(unitId: unitId, token: token),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportUrlRow extends ConsumerStatefulWidget {
  const _ExportUrlRow({required this.unitId, required this.token});
  final String unitId;
  final String token;

  @override
  ConsumerState<_ExportUrlRow> createState() => _ExportUrlRowState();
}

class _ExportUrlRowState extends ConsumerState<_ExportUrlRow> {
  bool _rotating = false;

  Future<void> _copy() async {
    final url = ref.read(icalSourceProvider).exportUrl(widget.token);
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Export URL copied')));
    }
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rotate export token?'),
        content: const Text(
          'The current export URL stops working immediately. Update it '
          'wherever it is pasted (e.g. Airbnb) right after rotating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Rotate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _rotating = true);
    try {
      await ref.read(icalSourceProvider).rotateExportToken(widget.unitId);
      ref.invalidate(icalExportTokenProvider(widget.unitId));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(icalSourceProvider).exportUrl(widget.token);
    return Row(
      children: [
        Expanded(child: SelectableText(url, key: const Key('ical-export-url'))),
        IconButton(
          key: const Key('ical-copy-url'),
          icon: const Icon(Icons.copy_outlined),
          tooltip: 'Copy',
          onPressed: _copy,
        ),
        IconButton(
          key: const Key('ical-rotate-token'),
          icon: _rotating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          tooltip: 'Rotate token',
          onPressed: _rotating ? null : _rotate,
        ),
      ],
    );
  }
}

class _ImportFeedsSection extends ConsumerWidget {
  const _ImportFeedsSection({required this.unitId, required this.clock});
  final String unitId;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedsAsync = ref.watch(icalFeedsProvider(unitId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AsyncView(
          value: feedsAsync,
          onRetry: () => ref.invalidate(icalFeedsProvider(unitId)),
          data: (feeds) => feeds.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: Spacing.md,
                    vertical: Spacing.sm,
                  ),
                  child: Text('No import feeds yet -- add one below.'),
                )
              : Column(
                  children: [
                    for (final feed in feeds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Spacing.sm),
                        child: _FeedTile(
                          feed: feed,
                          unitId: unitId,
                          clock: clock,
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: Spacing.sm),
        _AddFeedForm(unitId: unitId),
      ],
    );
  }
}

class _FeedTile extends ConsumerStatefulWidget {
  const _FeedTile({
    required this.feed,
    required this.unitId,
    required this.clock,
  });
  final IcalFeed feed;
  final String unitId;
  final DateTime Function() clock;

  @override
  ConsumerState<_FeedTile> createState() => _FeedTileState();
}

class _FeedTileState extends ConsumerState<_FeedTile> {
  bool _syncing = false;
  bool _removing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final result =
          await ref.read(icalSyncRunnerProvider).syncNow(widget.feed.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(syncOutcomeMessage(result))));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        ref.invalidate(icalFeedsProvider(widget.unitId));
      }
    }
  }

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await ref.read(icalSourceProvider).removeFeed(widget.feed.id);
      ref.invalidate(icalFeedsProvider(widget.unitId));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasLabel = feed.label != null && feed.label!.isNotEmpty;
    final busy = _syncing || _removing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hasLabel ? feed.label! : feed.url,
                key: const Key('ical-feed-title'), style: textTheme.bodyLarge),
            if (hasLabel)
              Text(feed.url,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            for (final line in feedStatusLines(feed, widget.clock()))
              _StatusLine(line: line),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_syncing)
                  const Row(
                    key: Key('ical-syncing'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: Spacing.sm),
                      Text('Syncing…'),
                    ],
                  )
                else
                  TextButton.icon(
                    key: const Key('ical-sync-feed'),
                    onPressed: busy ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                TextButton.icon(
                  key: const Key('ical-remove-feed'),
                  onPressed: busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One status line: warnings and errors carry an icon, never colour alone.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.line});
  final FeedLine line;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData? icon, Color color) = switch (line.tone) {
      FeedLineTone.neutral => (null, scheme.onSurfaceVariant),
      FeedLineTone.warning => (Icons.warning_amber_outlined, _warningColor),
      FeedLineTone.error => (Icons.error_outline, scheme.error),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.xs),
          ],
          Expanded(
            child: Text(
              line.text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddFeedForm extends ConsumerStatefulWidget {
  const _AddFeedForm({required this.unitId});
  final String unitId;

  @override
  ConsumerState<_AddFeedForm> createState() => _AddFeedFormState();
}

class _AddFeedFormState extends ConsumerState<_AddFeedForm> {
  final _url = TextEditingController();
  final _label = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Same reason as `BlockDatesScreen`'s `_reason` listener: the Add
    // button's enabled state depends on this text, which
    // TextEditingController does not trigger a rebuild for on its own.
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    _label.dispose();
    super.dispose();
  }

  bool get _urlValid => _feedUrlPattern.hasMatch(_url.text.trim());
  bool get _canAdd => !_busy && _urlValid;

  Future<void> _add() async {
    if (!_canAdd) return;
    setState(() => _busy = true);
    try {
      await ref.read(icalSourceProvider).addFeed(
            unitId: widget.unitId,
            url: _url.text.trim(),
            label: _label.text.trim().isEmpty ? null : _label.text.trim(),
          );
      ref.invalidate(icalFeedsProvider(widget.unitId));
      _url.clear();
      _label.clear();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add import feed', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('ical-feed-url'),
                controller: _url,
                decoration: InputDecoration(
                  labelText: 'Calendar URL',
                  hintText: 'https://www.airbnb.com/calendar/ical/....ics',
                  errorText: _url.text.trim().isEmpty || _urlValid
                      ? null
                      : 'Paste the calendar link (starts with https:// or '
                          'webcal://).',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('ical-feed-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'Airbnb',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              FilledButton(
                key: const Key('ical-add-feed'),
                onPressed: _canAdd ? _add : null,
                child: const Text('Add feed'),
              ),
            ],
          ),
        ),
      );
}

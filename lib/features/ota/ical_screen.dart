import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/ical_feed.dart';
import '../../data/repositories/ical_repository.dart';

final _timestamp = DateFormat('d MMM yyyy, HH:mm');

/// Every `ical_feeds` row for one unit -- RLS (`ical_feeds_admin`) scopes
/// this to admins; a customer/staff member gets zero rows, not an error,
/// same convention as every other admin-only list in this app.
final icalFeedsProvider = FutureProvider.family<List<IcalFeed>, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).feeds(unitId),
);

/// The unit's current export token, from `ical_export_tokens` (also
/// admin-only -- see `ical_repository.dart`'s header for why it is not a
/// column on `units`).
final icalExportTokenProvider = FutureProvider.family<String, String>(
  (ref, unitId) => ref.watch(icalSourceProvider).exportToken(unitId),
);

String _syncMessage(IcalSyncResult result) => switch (result.status) {
      'ok' => (result.conflicts ?? 0) > 0
          ? 'Synced -- ${result.conflicts} event(s) conflicted with an '
              'existing booking and were skipped'
          : 'Synced -- no conflicts',
      'requested' =>
        'Sync started -- pg_net fetches in the background; press Sync '
            'again in a moment to see the result',
      'pending' => 'Still waiting on the previous fetch -- try again shortly',
      'error' => result.error ?? 'Sync failed',
      _ => 'Sync: ${result.status}',
    };

/// `/admin/ota/:unitId` -- Airbnb/Booking.com calendar sync for one unit,
/// with no paid channel manager: an export URL to paste INTO the OTA
/// (top), and the list of feeds this unit imports FROM the OTA, with add,
/// remove and a manual Sync (below). Reachable only by an admin --
/// `ical_feeds_admin`/`ical_export_tokens_admin` RLS is the real
/// enforcement underneath, same as everywhere else in `/admin/*`.
class IcalScreen extends StatelessWidget {
  const IcalScreen({super.key, required this.unitId});

  final String unitId;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OTA calendar sync')),
        body: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _ExportSection(unitId: unitId),
            const SectionHeader(title: 'Import feeds'),
            _ImportFeedsSection(unitId: unitId),
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
              'Paste this into Airbnb under Listing -> Availability -> '
              'Sync calendars -> Add another calendar (Booking.com has an '
              'equivalent "Import calendar" field). It lists only busy '
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
  const _ImportFeedsSection({required this.unitId});
  final String unitId;

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
                        child: _FeedTile(feed: feed, unitId: unitId),
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
  const _FeedTile({required this.feed, required this.unitId});
  final IcalFeed feed;
  final String unitId;

  @override
  ConsumerState<_FeedTile> createState() => _FeedTileState();
}

class _FeedTileState extends ConsumerState<_FeedTile> {
  bool _busy = false;

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final result = await ref.read(icalSourceProvider).syncFeed(widget.feed.id);
      ref.invalidate(icalFeedsProvider(widget.unitId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_syncMessage(result))));
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(icalSourceProvider).removeFeed(widget.feed.id);
      ref.invalidate(icalFeedsProvider(widget.unitId));
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.feed;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasLabel = feed.label != null && feed.label!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hasLabel ? feed.label! : feed.url,
                      key: const Key('ical-feed-title'),
                      style: textTheme.bodyLarge),
                  if (hasLabel)
                    Text(feed.url,
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Spacing.xs),
                  Text(
                    feed.lastSyncedAt == null
                        ? 'Never synced'
                        : 'Last synced '
                            '${_timestamp.format(feed.lastSyncedAt!.toLocal())}',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (feed.lastError != null) ...[
                    const SizedBox(height: Spacing.xs),
                    Text(
                      feed.lastError!,
                      style: textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(Spacing.sm),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                key: const Key('ical-sync-feed'),
                icon: const Icon(Icons.sync),
                tooltip: 'Sync now',
                onPressed: _sync,
              ),
              IconButton(
                key: const Key('ical-remove-feed'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: _remove,
              ),
            ],
          ],
        ),
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

  bool get _canAdd => !_busy && _url.text.trim().isNotEmpty;

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
                decoration: const InputDecoration(
                  labelText: 'Calendar URL',
                  hintText: 'https://www.airbnb.com/calendar/ical/....ics',
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

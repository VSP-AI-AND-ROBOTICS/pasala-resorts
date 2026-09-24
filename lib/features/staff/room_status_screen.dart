import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import 'room_tile.dart';

/// How many rooms have each [RoomStatus]. Every status is present (zero
/// when no room has it), so the summary chips never jump around.
Map<RoomStatus, int> roomStatusCounts(List<RoomBoardEntry> entries) => {
      for (final status in RoomStatus.values)
        status: entries.where((e) => e.status == status).length,
    };

/// Grid columns for [width] logical pixels: two on a phone, four to six on
/// wider screens.
int roomGridColumns(double width) =>
    width < 600 ? 2 : (width ~/ 200).clamp(4, 6);

/// `/staff/rooms` -- the room status grid (REQ-06) of the current resort:
/// summary chips that count and filter, then one tile per active unit.
/// Every member of the resort can open it; pull to refresh.
class RoomStatusScreen extends ConsumerStatefulWidget {
  const RoomStatusScreen({super.key, this.clock = DateTime.now});

  /// What "n min" on a housekeeping line is measured against; injectable
  /// so tests do not depend on the wall clock.
  final DateTime Function() clock;

  @override
  ConsumerState<RoomStatusScreen> createState() => _RoomStatusScreenState();
}

class _RoomStatusScreenState extends ConsumerState<RoomStatusScreen> {
  RoomStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final resort = ref.watch(currentResortProvider);
    if (resort == null) {
      // The router only opens /staff/* with a current resort; this covers
      // the moment after sign-out, before the redirect fires.
      return const Scaffold(body: SizedBox.shrink());
    }
    final propertyId = resort.propertyId;
    final boardAsync = ref.watch(roomBoardProvider(propertyId));

    Future<void> refresh() => ref.refresh(roomBoardProvider(propertyId).future);

    return Scaffold(
      appBar: AppBar(title: const Text('Rooms')),
      body: AsyncView(
        value: boardAsync,
        onRetry: () => ref.invalidate(roomBoardProvider(propertyId)),
        empty: () => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              EmptyState(
                icon: Icons.meeting_room_outlined,
                title: 'No rooms yet',
                message: 'Active units of this resort show up here.',
              ),
            ],
          ),
        ),
        data: (entries) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _SummaryChips(
                counts: roomStatusCounts(entries),
                selected: _filter,
                onSelected: (status) =>
                    setState(() => _filter = _filter == status ? null : status),
              ),
              const SizedBox(height: Spacing.md),
              _RoomGrid(
                entries: [
                  for (final e in entries)
                    if (_filter == null || e.status == _filter) e,
                ],
                emptyLabel: _filter == null
                    ? ''
                    : 'No ${_filter!.label} rooms right now.',
                now: widget.clock(),
                onTap: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryChips extends StatelessWidget {
  const _SummaryChips({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  final Map<RoomStatus, int> counts;
  final RoomStatus? selected;
  final ValueChanged<RoomStatus> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final status in RoomStatus.values)
            FilterChip(
              key: Key('room-filter-${status.name}'),
              avatar: Icon(status.icon, size: 18, color: status.color),
              label: Text('${status.label} (${counts[status] ?? 0})'),
              selected: selected == status,
              showCheckmark: false,
              onSelected: (_) => onSelected(status),
            ),
        ],
      );
}

class _RoomGrid extends StatelessWidget {
  const _RoomGrid({
    required this.entries,
    required this.emptyLabel,
    required this.now,
    required this.onTap,
  });

  final List<RoomBoardEntry> entries;
  final String emptyLabel;
  final DateTime now;

  /// Null for a read-only viewer: tiles are not tappable.
  final void Function(RoomBoardEntry entry)? onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
        child: Text(emptyLabel,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final columns = roomGridColumns(constraints.maxWidth);
      final width =
          ((constraints.maxWidth - Spacing.sm * (columns - 1)) / columns)
              .floorToDouble();
      return Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.sm,
        children: [
          for (final entry in entries)
            SizedBox(
              width: width,
              child: RoomTile(
                entry: entry,
                now: now,
                onTap: onTap == null ? null : () => onTap!(entry),
              ),
            ),
        ],
      );
    });
  }
}

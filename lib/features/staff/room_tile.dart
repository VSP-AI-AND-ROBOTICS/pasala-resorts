import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/room_status.dart';

/// An icon and a label in a tinted pill. The label always travels with the
/// colour, so a status is never told by colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      );
}

/// The derived [RoomStatus] as a pill.
class RoomStatusChip extends StatelessWidget {
  const RoomStatusChip({super.key, required this.status});
  final RoomStatus status;

  @override
  Widget build(BuildContext context) =>
      StatusPill(icon: status.icon, label: status.label, color: status.color);
}

/// "Housekeeping: Hari, 25 min" -- the housekeeper's first name and the
/// whole minutes since housekeeping was sent.
String housekeepingLine(RoomBoardEntry entry, DateTime now) {
  final fullName = entry.housekeeperName?.trim() ?? '';
  final name = fullName.isEmpty ? 'unassigned' : fullName.split(' ').first;
  return 'Housekeeping: $name, ${entry.minutesSinceDispatch(now) ?? 0} min';
}

/// One room on the grid. [onTap] is null for a read-only viewer.
class RoomTile extends StatelessWidget {
  const RoomTile({super.key, required this.entry, required this.now, this.onTap});

  final RoomBoardEntry entry;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final muted = textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final occupied = entry.status == RoomStatus.occupied;

    Widget gap(Widget child) => Padding(
          padding: const EdgeInsets.only(top: Spacing.xs),
          child: child,
        );

    return Card(
      key: Key('room-tile-${entry.unitId}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                  style: textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              gap(RoomStatusChip(status: entry.status)),
              if (occupied && entry.state == RoomState.dirty)
                gap(StatusPill(
                  icon: RoomStatus.cleaning.icon,
                  label: 'Needs cleaning',
                  color: RoomStatus.cleaning.color,
                )),
              if (occupied && entry.state == RoomState.outOfOrder)
                gap(StatusPill(
                  icon: RoomStatus.maintenance.icon,
                  label: 'Out of order',
                  color: RoomStatus.maintenance.color,
                )),
              if (entry.state == RoomState.outOfOrder && entry.reason != null)
                gap(Text(entry.reason!,
                    style: muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (occupied && entry.guestFirstName != null)
                gap(Text('Guest: ${entry.guestFirstName}', style: muted)),
              if (entry.arrivingToday) gap(Text('Arriving today', style: muted)),
              if (entry.isDayUse) gap(Text('Day use', style: muted)),
              if (entry.hasOpenHousekeeping)
                gap(Text(housekeepingLine(entry, now),
                    style: muted, maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (entry.overdue)
                gap(StatusPill(
                  icon: Icons.warning_amber_outlined,
                  label: 'Overdue',
                  color: scheme.error,
                )),
            ],
          ),
        ),
      ),
    );
  }
}

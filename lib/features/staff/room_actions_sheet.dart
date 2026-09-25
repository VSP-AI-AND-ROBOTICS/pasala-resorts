import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import 'room_tile.dart';

/// What the person chose in the room sheet. The sheet only decides; the
/// grid screen carries it out, so every call and its error handling live
/// in one place.
sealed class RoomAction {
  const RoomAction();
}

class SetRoomStateAction extends RoomAction {
  const SetRoomStateAction(this.state, {this.reason});
  final RoomState state;
  final String? reason;
}

class DispatchAction extends RoomAction {
  const DispatchAction(this.assigneeId, {this.note});
  final String assigneeId;
  final String? note;
}

class OpenPathAction extends RoomAction {
  const OpenPathAction(this.path);
  final String path;
}

Future<RoomAction?> showRoomActionsSheet(
  BuildContext context, {
  required RoomBoardEntry entry,
  required String propertyId,
}) =>
    showModalBottomSheet<RoomAction>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RoomActionsSheet(entry: entry, propertyId: propertyId),
    );

/// The actions for one room: its stored state (Available / Needs cleaning /
/// Maintenance), Send housekeeping, and links to check-in and check-out.
/// Occupied is shown for completeness but is set only by check-in/out.
class RoomActionsSheet extends StatelessWidget {
  const RoomActionsSheet({
    super.key,
    required this.entry,
    required this.propertyId,
  });

  final RoomBoardEntry entry;
  final String propertyId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    Widget? tick(RoomState state) =>
        entry.state == state ? const Icon(Icons.check) : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              child: Row(
                children: [
                  Expanded(child: Text(entry.name, style: textTheme.titleMedium)),
                  RoomStatusChip(status: entry.status),
                ],
              ),
            ),
            const SizedBox(height: Spacing.sm),
            ListTile(
              key: const Key('room-action-occupied'),
              enabled: false,
              leading: Icon(RoomStatus.occupied.icon),
              title: const Text('Occupied'),
              subtitle: const Text('Set by check-in and check-out'),
              trailing: entry.status == RoomStatus.occupied
                  ? const Icon(Icons.check)
                  : null,
            ),
            ListTile(
              key: const Key('room-action-available'),
              leading: Icon(RoomStatus.available.icon,
                  color: RoomStatus.available.color),
              title: const Text('Available'),
              subtitle: const Text('Clean and ready'),
              trailing: tick(RoomState.ready),
              onTap: () => Navigator.of(context)
                  .pop(const SetRoomStateAction(RoomState.ready)),
            ),
            ListTile(
              key: const Key('room-action-dirty'),
              leading: Icon(RoomStatus.cleaning.icon,
                  color: RoomStatus.cleaning.color),
              title: const Text('Needs cleaning'),
              trailing: tick(RoomState.dirty),
              onTap: () => Navigator.of(context)
                  .pop(const SetRoomStateAction(RoomState.dirty)),
            ),
            ListTile(
              key: const Key('room-action-maintenance'),
              leading: Icon(RoomStatus.maintenance.icon,
                  color: RoomStatus.maintenance.color),
              title: const Text('Maintenance'),
              subtitle: Text(entry.state == RoomState.outOfOrder &&
                      entry.reason != null
                  ? entry.reason!
                  : 'Out of order, with a reason'),
              trailing: tick(RoomState.outOfOrder),
              onTap: () async {
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => const MaintenanceReasonDialog(),
                );
                if (reason != null && context.mounted) {
                  Navigator.of(context).pop(
                      SetRoomStateAction(RoomState.outOfOrder, reason: reason));
                }
              },
            ),
            const Divider(),
            ListTile(
              key: const Key('room-action-dispatch'),
              enabled: !entry.hasOpenHousekeeping,
              leading: const Icon(Icons.send_outlined),
              title: const Text('Send housekeeping'),
              subtitle: entry.hasOpenHousekeeping
                  ? Text(
                      'Already sent to ${entry.housekeeperName ?? 'a staff member'}')
                  : null,
              onTap: () async {
                final action = await showDialog<DispatchAction>(
                  context: context,
                  builder: (_) => DispatchDialog(
                      propertyId: propertyId, unitName: entry.name),
                );
                if (action != null && context.mounted) {
                  Navigator.of(context).pop(action);
                }
              },
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  TextButton.icon(
                    key: const Key('room-link-check-in'),
                    icon: const Icon(Icons.login_outlined),
                    label: const Text('Check-in'),
                    onPressed: () => Navigator.of(context)
                        .pop(const OpenPathAction('/admin/check-in')),
                  ),
                  TextButton.icon(
                    key: const Key('room-link-check-out'),
                    icon: const Icon(Icons.logout_outlined),
                    label: const Text('Check-out'),
                    onPressed: () => Navigator.of(context)
                        .pop(const OpenPathAction('/admin/check-out')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks why a room is out of order. Returns the trimmed reason, or null
/// when cancelled. A blank reason is refused here, before the server's
/// P0030 would.
class MaintenanceReasonDialog extends StatefulWidget {
  const MaintenanceReasonDialog({super.key});

  @override
  State<MaintenanceReasonDialog> createState() =>
      _MaintenanceReasonDialogState();
}

class _MaintenanceReasonDialogState extends State<MaintenanceReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter a reason');
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Why is it out of order?'),
        content: TextField(
          key: const Key('maintenance-reason'),
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: 'Reason',
            hintText: 'e.g. AC not cooling',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('maintenance-submit'),
            onPressed: _submit,
            child: const Text('Mark Maintenance'),
          ),
        ],
      );
}

/// Picks one of the resort's `staff` members and an optional note.
/// Returns the choice, or null when cancelled.
class DispatchDialog extends ConsumerStatefulWidget {
  const DispatchDialog({
    super.key,
    required this.propertyId,
    required this.unitName,
  });

  final String propertyId;
  final String unitName;

  @override
  ConsumerState<DispatchDialog> createState() => _DispatchDialogState();
}

class _DispatchDialogState extends ConsumerState<DispatchDialog> {
  final _note = TextEditingController();
  String? _assigneeId;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(dispatchableStaffProvider(widget.propertyId));

    return AlertDialog(
      title: Text('Send housekeeping to ${widget.unitName}'),
      content: SizedBox(
        width: 360,
        child: staffAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Spacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Text(FailureView.messageFor(error)),
          data: (staff) => staff.isEmpty
              ? const Text(
                  'No Staff / Incharge members yet. An owner can add one in Team.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: const Key('dispatch-assignee'),
                      initialValue: _assigneeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Housekeeper'),
                      items: [
                        for (final s in staff)
                          DropdownMenuItem(
                              value: s.userId, child: Text(s.displayName)),
                      ],
                      onChanged: (value) => setState(() => _assigneeId = value),
                    ),
                    const SizedBox(height: Spacing.sm),
                    TextField(
                      key: const Key('dispatch-note'),
                      controller: _note,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Note (optional)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('dispatch-submit'),
          onPressed: _assigneeId == null
              ? null
              : () {
                  // Read the controller directly rather than a `build`-time
                  // local: `enterText` in tests (and a fast real typist) can
                  // still have the note field's setState unflushed when this
                  // is invoked, and a stale closure would silently drop it.
                  final note = _note.text.trim();
                  Navigator.of(context).pop(DispatchAction(
                    _assigneeId!,
                    note: note.isEmpty ? null : note,
                  ));
                },
          child: const Text('Send'),
        ),
      ],
    );
  }
}

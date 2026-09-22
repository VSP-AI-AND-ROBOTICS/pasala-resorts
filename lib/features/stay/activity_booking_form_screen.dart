import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/activity.dart';
import '../../data/repositories/activity_repository.dart';

/// Date/time/people picker for one [activity], reusing the date-picker
/// conventions already used by the Owner flow's food-sales/expenses forms.
class ActivityBookingFormScreen extends ConsumerStatefulWidget {
  const ActivityBookingFormScreen({
    super.key,
    required this.reservationId,
    required this.activity,
  });

  final String reservationId;
  final Activity activity;

  @override
  ConsumerState<ActivityBookingFormScreen> createState() =>
      _ActivityBookingFormScreenState();
}

class _ActivityBookingFormScreenState
    extends ConsumerState<ActivityBookingFormScreen> {
  DateTime _date = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 17, minute: 0);
  int _people = 1;
  bool _busy = false;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(activityRepositoryProvider).bookActivity(
            reservationId: widget.reservationId,
            activityId: widget.activity.id,
            bookingDate: _date,
            startTime:
                '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
            people: _people,
          );
      if (!mounted) return;
      ref.invalidate(myActivityBookingsProvider(widget.reservationId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Activity booked')));
      context.pop();
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    final amount = activity.pricePerPerson * _people;

    return Scaffold(
      appBar: AppBar(title: Text(activity.name)),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          if (activity.description != null) ...[
            Text(activity.description!),
            const SizedBox(height: Spacing.lg),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(formatDay(_date)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Time'),
            subtitle: Text(_time.format(context)),
            trailing: const Icon(Icons.schedule_outlined),
            onTap: _pickTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('People'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _people > 1
                      ? () => setState(() => _people--)
                      : null,
                ),
                Text('$_people', style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() => _people++),
                ),
              ],
            ),
          ),
          const Divider(height: Spacing.xl),
          Row(
            children: [
              const Expanded(child: Text('Total')),
              Text(formatInr(amount),
                  style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: Text(_busy ? 'Booking…' : 'Confirm'),
          ),
        ],
      ),
    );
  }
}

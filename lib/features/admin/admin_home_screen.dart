import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/format.dart';
import '../../core/greeting.dart';
import '../../core/theme/app_assets.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/reservation.dart';
import '../../data/models/room_status.dart';
import '../../data/repositories/room_status_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/review_repository.dart';
import '../browse/providers.dart';
import '../reports/providers.dart';
import '../staff/providers.dart';

/// The soonest not-yet-arrived confirmed booking -- "not yet arrived" means
/// its start is today or later, so a confirmed booking whose dates already
/// passed (an admin never got around to checking it in) never displays as
/// tomorrow's arrival. Checked-in bookings are excluded: once a guest has
/// physically arrived, that's no longer an upcoming arrival to plan for.
Reservation? nextArrival(List<Reservation> bookings, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final upcoming = bookings.where((r) =>
      r.kind == ReservationKind.booking &&
      r.status == ReservationStatus.confirmed &&
      !r.start.toLocal().isBefore(today)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  return upcoming.isEmpty ? null : upcoming.first;
}

/// True the moment any guest is actually checked in -- not derived from
/// dates, since a checked-in reservation is definitionally "someone is here
/// right now" regardless of when its booked nights started or end.
bool isFarmhouseOccupied(List<Reservation> bookings) => bookings.any(
    (r) => r.kind == ReservationKind.booking &&
        r.status == ReservationStatus.checkedIn);

/// Every non-cancelled booking-kind reservation whose stay starts in the
/// same calendar month as [now], on or before today -- the Business
/// Snapshot's "This Month" count. A cancelled booking contributes no
/// revenue and should not inflate the count either.
///
/// Matches `dashboard_summary()`'s `month_revenue` (month-to-date, not the
/// full calendar month) -- both were once on different windows, so a
/// booking arriving later this month counted toward "Bookings" today but
/// its revenue wouldn't show up until its arrival date, silently dragging
/// "Avg. Booking Value" below what any of the counted bookings actually
/// paid. Reproduced live: 4 bookings this month, but only 2 had already
/// contributed to the ₹59,000 month-to-date revenue figure -- the card
/// showed a ₹14,750 average when the two real bookings averaged ₹29,500.
List<Reservation> bookingsThisMonth(List<Reservation> bookings, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return bookings
      .where((r) =>
          r.kind == ReservationKind.booking &&
          r.status != ReservationStatus.cancelled &&
          r.start.toLocal().year == now.year &&
          r.start.toLocal().month == now.month &&
          !DateUtils.dateOnly(r.start.toLocal()).isAfter(today))
      .toList();
}

/// `"14:00"` -> `"2:00 PM"`. Postgres `time` columns round-trip via
/// `Property.checkInTime`/`checkOutTime` as 24-hour `HH:mm`; the dashboard's
/// arrival cards read better in the 12-hour form a guest actually thinks in.
String formatTimeOfDay(String hhmm) {
  final parts = hhmm.split(':');
  var hour = int.parse(parts[0]);
  final minute = parts[1];
  final period = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  return '$hour:$minute $period';
}

/// "Today" / "Tomorrow" / a plain formatted date -- used wherever a card
/// names a specific day relative to now, rather than always spelling out a
/// full date the way [formatDay] does.
String relativeDayLabel(DateTime day, DateTime now) {
  final d = DateTime(day.year, day.month, day.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return formatDay(day);
}

/// "Just now" / "N hours/days ago" / a plain formatted date once it's old
/// enough that a relative count stops being useful. Used for the Guest
/// Experience card's "Last Review" timestamp.
String relativeTime(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inDays >= 30) return formatDate(from);
  if (diff.inDays >= 1) {
    return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return 'Just now';
}

/// Whether every room's stored state is `ready` -- an occupied room counts
/// as ready unless someone marked it for cleaning or maintenance.
bool allRoomsReady(List<RoomBoardEntry> rooms) =>
    rooms.every((r) => r.state == RoomState.ready);

/// The Preparation line of Today's Focus, from the room board's stored
/// states (not the derived status, so an occupied room that needs cleaning
/// still counts).
String roomReadinessLabel(List<RoomBoardEntry> rooms) {
  if (rooms.isEmpty) return 'No rooms set up';
  final toClean = rooms.where((r) => r.state == RoomState.dirty).length;
  final maintenance = rooms.where((r) => r.state == RoomState.outOfOrder).length;
  if (toClean == 0 && maintenance == 0) return 'All rooms ready ✓';
  return [
    if (toClean > 0) '$toClean to clean',
    if (maintenance > 0) '$maintenance in maintenance',
  ].join(' · ');
}

/// This screen shows exactly one resort -- the signed-in admin's current
/// one (`currentResortProvider`), which by Task 14's redirect always exists
/// by the time `/admin` is reachable. Resolves to `null` while loading or if
/// that resort has no units yet, so callers degrade to a disabled action
/// rather than crashing.
final _primaryUnitIdProvider = FutureProvider<String?>((ref) async {
  final propertyId = ref.watch(currentResortProvider)!.propertyId;
  final units = await ref.watch(unitsProvider(propertyId).future);
  return units.isEmpty ? null : units.first.id;
});

/// `/admin` landing page -- reachable only by `isAdmin` users (the router
/// redirects everyone else to `/404`). Every figure shown here is either
/// read straight from the database (bookings, reviews, `dashboard_summary`)
/// or derived from those rows client-side; nothing is invented. The
/// Farmhouse Readiness checklist is the one deliberate exception -- see its
/// widget doc below.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final firstName = user?.fullName?.split(' ').first ?? 'Admin';
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // No AppBar of its own: `AppShell` (this screen's parent, wrapping
      // every signed-in route) already renders the "Pasala Resorts" brand
      // bar, and now also an "Admin" label + profile avatar (opening the
      // account sheet with sign out) -- see `AppShell._adminActions`. A
      // second identity row here would just duplicate that.
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          Text('${greetingFor(now)}, $firstName 👋',
              style: textTheme.headlineSmall),
          const SizedBox(height: Spacing.xs),
          Text(
            fullDateFor(now),
            style:
                textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Spacing.md),
          const _FarmhouseStatusCard(),
          const SizedBox(height: Spacing.md),
          const _TodaysFocus(),
          const SizedBox(height: Spacing.md),
          const _QuickActions(),
          const SizedBox(height: Spacing.md),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _FarmhouseReadinessCard()),
              SizedBox(width: Spacing.md),
              Expanded(child: _GuestExperienceCard()),
            ],
          ),
          const SizedBox(height: Spacing.md),
          const _BusinessSnapshotCard(),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(Spacing.md), child: child),
      );
}

Widget _eyebrow(BuildContext context, String text) => Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
    );

/// The property photo, a READY/OCCUPIED status derived from
/// [isFarmhouseOccupied], the soonest upcoming arrival's day/time, and a
/// link to that unit's block-dates calendar (the closest existing screen to
/// "View Calendar" -- there is no separate admin calendar view).
class _FarmhouseStatusCard extends ConsumerWidget {
  const _FarmhouseStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final property = ref.watch(propertyProvider(propertyId)).value;
    final bookings = ref.watch(allBookingsProvider(propertyId)).value ?? const [];
    final unitId = ref.watch(_primaryUnitIdProvider).value;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final occupied = isFarmhouseOccupied(bookings);
    final arrival = nextArrival(bookings, DateTime.now());

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, 'FARMHOUSE STATUS'),
          const SizedBox(height: Spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                child: Image.asset(AppAssets.heroNightAerial,
                    width: 96, height: 96, fit: BoxFit.cover),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(property?.name ?? 'Pasala Farm House',
                        style: textTheme.titleMedium),
                    const SizedBox(height: Spacing.xs),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: occupied ? scheme.error : scheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(occupied ? 'OCCUPIED' : 'READY',
                            style: textTheme.labelLarge?.copyWith(
                                color: occupied ? scheme.error : scheme.primary,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                    Text(
                      occupied
                          ? 'A guest is currently checked in'
                          : 'Available for booking',
                      style: textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: Spacing.lg),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 20, color: scheme.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next Arrival', style: textTheme.bodyMedium),
                    Text(
                      arrival == null
                          ? 'No upcoming arrivals'
                          : '${relativeDayLabel(arrival.start.toLocal(), DateTime.now())} · '
                              '${formatTimeOfDay(property?.checkInTime ?? '14:00')}',
                      style: textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: unitId == null
                  ? null
                  : () => context.push('/admin/block/$unitId'),
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text('View Calendar'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arrival and Payment both describe the SAME soonest upcoming booking (see
/// [nextArrival]) -- one coherent story rather than two unrelated figures.
/// Preparation reads the room board -- see [roomReadinessLabel].
class _TodaysFocus extends ConsumerWidget {
  const _TodaysFocus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final bookings = ref.watch(allBookingsProvider(propertyId)).value ?? const [];
    final arrival = nextArrival(bookings, DateTime.now());
    final preparation = ref.watch(roomBoardProvider(propertyId)).when(
          data: roomReadinessLabel,
          loading: () => 'Checking rooms…',
          error: (_, _) => 'Room status unavailable',
        );
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final paidAsync = arrival == null
        ? null
        : ref.watch(paidAmountProvider(arrival.id));

    Widget column({
      required IconData icon,
      required Color iconColor,
      required Color background,
      required String label,
      required Widget content,
    }) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: background,
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(height: Spacing.xs),
              Text(label,
                  style: textTheme.labelMedium?.copyWith(color: iconColor)),
              const SizedBox(height: 2),
              content,
            ],
          ),
        );

    final Widget arrivalContent = arrival == null
        ? Text('No arrivals', style: textTheme.bodySmall)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(arrival.customerName ?? 'Guest',
                  style: textTheme.titleSmall),
              Text('${arrival.guests ?? 0} Guests',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Text(
                relativeDayLabel(arrival.start.toLocal(), DateTime.now()),
                style: textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          );

    final Widget paymentContent = arrival == null
        ? Text('—', style: textTheme.bodySmall)
        : (paidAsync?.value == null
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Builder(builder: (context) {
                final total = arrival.quote?.total ?? 0;
                final paid = paidAsync!.value!;
                final balance = total - paid;
                if (balance <= 0) {
                  return Text('Fully paid', style: textTheme.titleSmall);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatInr(balance),
                        style: textTheme.titleSmall
                            ?.copyWith(color: scheme.error)),
                    Text('From 1 Booking',
                        style: textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                );
              }));

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, "TODAY'S FOCUS"),
          const SizedBox(height: Spacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column(
                icon: Icons.schedule,
                iconColor: scheme.primary,
                background: scheme.primaryContainer,
                label: 'Arrival',
                content: arrivalContent,
              ),
              const SizedBox(width: Spacing.sm),
              column(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: scheme.error,
                background: scheme.errorContainer,
                label: 'Payment',
                content: paymentContent,
              ),
              const SizedBox(width: Spacing.sm),
              column(
                icon: Icons.cleaning_services_outlined,
                iconColor: scheme.tertiary,
                background: scheme.tertiaryContainer,
                label: 'Preparation',
                content: Text(preparation,
                    key: const Key('preparation-rooms'),
                    style: textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

typedef _QuickAction = ({
  IconData icon,
  String label,
  Color color,
});

/// Every tile that has a real, already-built destination navigates there;
/// the rest show a coming-soon message rather than a dead end -- same
/// pattern as the property page's "New Booking" button.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  void _comingSoon(BuildContext context, String action) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$action is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final unitId = ref.watch(_primaryUnitIdProvider).value;
    final propertyId = ref.watch(currentResortProvider)!.propertyId;

    final actions = <(_QuickAction, VoidCallback)>[
      (
        (icon: Icons.add_circle_outline, label: 'New Booking', color: scheme.primary),
        () => context.push('/property/$propertyId'),
      ),
      (
        (icon: Icons.event_busy_outlined, label: 'Block Date', color: Colors.indigo),
        unitId == null
            ? () => _comingSoon(context, 'Block Date')
            : () => context.push('/admin/block/$unitId'),
      ),
      (
        (icon: Icons.login_outlined, label: 'Check-in', color: scheme.primary),
        () => context.push('/admin/check-in'),
      ),
      (
        (icon: Icons.logout_outlined, label: 'Check-out', color: scheme.tertiary),
        () => context.push('/admin/check-out'),
      ),
      (
        (icon: Icons.meeting_room_outlined, label: 'Rooms', color: Colors.teal),
        () => context.push('/staff/rooms'),
      ),
      (
        (icon: Icons.restaurant_outlined, label: 'Food Order', color: Colors.deepOrange),
        () => context.push('/admin/kitchen-orders'),
      ),
      (
        (icon: Icons.build_outlined, label: 'Maintenance', color: Colors.purple),
        () => context.push('/admin/maintenance'),
      ),
      (
        (icon: Icons.campaign_outlined, label: 'Send Message', color: Colors.blue),
        () => context.push('/admin/outbox'),
      ),
      (
        (icon: Icons.receipt_long_outlined, label: 'Add Expense', color: scheme.primary),
        () => context.push('/owner/expenses'),
      ),
    ];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, 'QUICK ACTIONS'),
          const SizedBox(height: Spacing.md),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Spacing.sm,
            crossAxisSpacing: Spacing.sm,
            childAspectRatio: 0.9,
            children: [
              for (final (action, onTap) in actions)
                _QuickActionTile(
                  key: Key('quick-action-${action.label}'),
                  action: action,
                  onTap: onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({super.key, required this.action, required this.onTap});

  final _QuickAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
      child: Container(
        decoration: BoxDecoration(
          color: action.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
        ),
        padding: const EdgeInsets.all(Spacing.xs),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: action.color),
            const SizedBox(height: Spacing.xs),
            Text(
              action.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A readiness checklist. Only "Rooms / Cottages" is backed by data -- the
/// room board's stored states (see [allRoomsReady]); Pool, Garden, Kitchen
/// and Wi-Fi have no status anywhere in the app and stay a fixed checklist.
/// The Overall Status pill follows the rooms line: READY, ATTENTION when a
/// room needs cleaning or is out of order, or a dash while the board is
/// loading or unavailable.
class _FarmhouseReadinessCard extends ConsumerWidget {
  const _FarmhouseReadinessCard();

  static const _fixedItems = ['Pool', 'Garden', 'Kitchen', 'Wi-Fi'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final rooms = ref.watch(roomBoardProvider(propertyId)).value;
    final roomsReady = rooms == null ? null : allRoomsReady(rooms);

    Widget row(String item, IconData icon, Color color, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                  child: Text(item,
                      style: textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis)),
              Icon(icon, size: 16, color: color),
            ],
          ),
        );

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, 'FARMHOUSE READINESS'),
          const SizedBox(height: Spacing.sm),
          row(
            'Rooms / Cottages',
            switch (roomsReady) {
              true => Icons.check_circle,
              false => Icons.error_outline,
              null => Icons.remove_circle_outline,
            },
            switch (roomsReady) {
              true => scheme.primary,
              false => RoomStatus.cleaning.color,
              null => scheme.onSurfaceVariant,
            },
            key: const Key('readiness-rooms'),
          ),
          for (final item in _fixedItems)
            row(item, Icons.check_circle, scheme.primary),
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Spacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Overall Status',
                    style: textTheme.labelSmall
                        ?.copyWith(color: scheme.onPrimaryContainer)),
                const Spacer(),
                Text(
                  switch (roomsReady) {
                    true => 'READY',
                    false => 'ATTENTION',
                    null => '—',
                  },
                  key: const Key('readiness-overall'),
                  style: textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The real average rating and most recent review, from every review of
/// the current resort -- see [ReviewRepository.forProperty]. "View
/// Reviews" opens the standalone list.
class _GuestExperienceCard extends ConsumerWidget {
  const _GuestExperienceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final reviewsAsync = ref.watch(propertyReviewsProvider(propertyId));
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final reviews = reviewsAsync.value ?? const [];
    final average = reviews.isEmpty
        ? null
        : reviews.map((r) => r.overallRating).reduce((a, b) => a + b) /
            reviews.length;
    final latest = reviews.isEmpty ? null : reviews.first;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(context, 'GUEST EXPERIENCE'),
          const SizedBox(height: Spacing.sm),
          if (average == null)
            Text('No reviews yet', style: textTheme.bodySmall)
          else
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 20),
                const SizedBox(width: Spacing.xs),
                Text(average.toStringAsFixed(1),
                    style: textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          Text('Average Rating',
              style:
                  textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          if (latest != null) ...[
            const SizedBox(height: Spacing.sm),
            Text('Last Review',
                style: textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (latest.createdAt != null)
              Text(relativeTime(latest.createdAt!.toLocal(), DateTime.now()),
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            if (latest.feedback.isNotEmpty)
              Text('"${latest.feedback}"',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: Spacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.push('/admin/reviews'),
              child: const Text('View Reviews'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Revenue is the server's own figure from `dashboard_summary()` -- never
/// re-derived. Bookings count is computed client-side from the same
/// already-fetched `allBookings()` list (see [bookingsThisMonth]); average
/// booking value divides the two. "This Month" is a static label, not an
/// interactive period picker -- see the design discussion before this
/// screen was built.
class _BusinessSnapshotCard extends ConsumerWidget {
  const _BusinessSnapshotCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A screen reached without a current resort is impossible after Task
    // 14's redirect.
    final propertyId = ref.watch(currentResortProvider)!.propertyId;
    final summaryAsync = ref.watch(dashboardSummaryProvider(propertyId));
    final bookings = ref.watch(allBookingsProvider(propertyId)).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final monthRevenue = summaryAsync.value?.monthRevenue ?? 0;
    final count = bookingsThisMonth(bookings, DateTime.now()).length;
    final avg = count == 0 ? 0 : monthRevenue / count;

    Widget stat(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: Spacing.xs),
              Text(value,
                  style: textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(label,
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        );

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _eyebrow(context, 'BUSINESS SNAPSHOT'),
              const Spacer(),
              Text('This Month',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              stat(Icons.event_note_outlined, '$count', 'Bookings'),
              stat(Icons.currency_rupee, formatInr(monthRevenue), 'Revenue'),
              stat(Icons.bar_chart, formatInr(avg), 'Avg. Booking Value'),
            ],
          ),
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.push('/admin/reports'),
              child: const Text('View Reports & Analytics'),
            ),
          ),
        ],
      ),
    );
  }
}

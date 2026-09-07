import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/reservation.dart';
import '../browse/providers.dart' show propertiesProvider;
import '../staff/providers.dart';

/// The mockup's four guest-facing states, plus [blocks] -- the pre-existing
/// escape hatch for finding (and thus undoing) an admin block, which has no
/// customer or quote and so cannot appear under any of the other four.
enum BookingStatusFilter { all, confirmed, pending, cancelled, completed, blocks }

/// Reservations narrowed to [filter]. `all`/`confirmed`/`pending`/
/// `cancelled`/`completed` only ever look at kind `booking` -- i.e. actual
/// guest bookings -- because listing an admin block alongside them as a
/// "booking" would be misleading; blocks have no customer or quote.
/// [BookingStatusFilter.blocks] is the one dedicated escape hatch: without
/// it, a block could only ever be found (and thus only ever be undone) via
/// psql, since nothing else in the app surfaces its id. Pure and top-level
/// so the filter logic is directly unit-testable without pumping a widget.
List<Reservation> filterBookings(
  List<Reservation> all,
  BookingStatusFilter filter,
) {
  if (filter == BookingStatusFilter.blocks) {
    return all.where((r) => r.kind == ReservationKind.block).toList();
  }
  final bookings = all.where((r) => r.kind == ReservationKind.booking);
  return switch (filter) {
    BookingStatusFilter.all => bookings.toList(),
    // A checked-in guest is still on an active, confirmed stay -- the
    // mockup has no separate tab for it, so it stays under Confirmed.
    BookingStatusFilter.confirmed => bookings
        .where((r) =>
            r.status == ReservationStatus.confirmed ||
            r.status == ReservationStatus.checkedIn)
        .toList(),
    // Neither a hold nor a pending-payment reservation has been paid for
    // yet -- both read as "awaiting the guest" from an admin's perspective.
    BookingStatusFilter.pending => bookings
        .where((r) =>
            r.status == ReservationStatus.hold ||
            r.status == ReservationStatus.pendingPayment)
        .toList(),
    BookingStatusFilter.cancelled =>
      bookings.where((r) => r.status == ReservationStatus.cancelled).toList(),
    BookingStatusFilter.completed => bookings
        .where((r) => r.status == ReservationStatus.checkedOut)
        .toList(),
    BookingStatusFilter.blocks => const [], // unreachable, handled above
  };
}

String _filterLabel(BookingStatusFilter filter) => switch (filter) {
      BookingStatusFilter.all => 'All',
      BookingStatusFilter.confirmed => 'Confirmed',
      BookingStatusFilter.pending => 'Pending',
      BookingStatusFilter.cancelled => 'Cancelled',
      BookingStatusFilter.completed => 'Completed',
      BookingStatusFilter.blocks => 'Blocks',
    };

/// A short, human-scannable label derived from a reservation's UUID -- e.g.
/// `PR3F2A`. Purely a display convenience: it carries no meaning
/// server-side and nothing ever looks a booking up by it. The underlying
/// [Reservation.id] remains the real identifier used for navigation,
/// cancellation, etc. -- this just gives the admin something short to scan
/// and search by, the way the mockup's "PR1234" does.
String bookingCode(String reservationId) {
  final hex = reservationId.replaceAll('-', '');
  final slice = hex.length >= 4 ? hex.substring(0, 4) : hex.padRight(4, '0');
  return 'PR${slice.toUpperCase()}';
}

/// True if [reservation] matches [query] on its booking code, guest name,
/// or phone -- a case-insensitive substring match against whichever of
/// those three the admin actually typed. An empty query always matches.
bool bookingMatchesSearch(Reservation reservation, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return bookingCode(reservation.id).toLowerCase().contains(q) ||
      (reservation.customerName?.toLowerCase().contains(q) ?? false) ||
      (reservation.customerPhone?.toLowerCase().contains(q) ?? false);
}

/// `/admin/bookings` -- every reservation the admin may see (RLS grants
/// admin/super_admin all rows), filterable by status and searchable by
/// booking code / guest name / phone. Taps through to the same
/// `/booking-detail/:id` the customer's own My Bookings screen uses, whose
/// cancel action is already permitted for admins by `cancel_booking`.
class AdminBookingsScreen extends ConsumerStatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  ConsumerState<AdminBookingsScreen> createState() =>
      _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends ConsumerState<AdminBookingsScreen> {
  BookingStatusFilter _filter = BookingStatusFilter.all;
  final _searchController = TextEditingController();
  String _search = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _newBookingComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Creating a booking from here is coming soon.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(allBookingsProvider);
    final scheme = Theme.of(context).colorScheme;
    final properties = ref.watch(propertiesProvider).value ?? const [];
    final propertyId = properties.isEmpty ? null : properties.first.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bookings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Spacing.md),
            child: FilledButton.icon(
              onPressed: propertyId == null
                  ? _newBookingComingSoon
                  : () => context.push('/property/$propertyId'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Booking'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, Spacing.sm),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _search = value),
              decoration: InputDecoration(
                hintText: 'Search by Booking ID / Guest / Mobile',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: scheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PasalaTokens.radiusSm),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
              scrollDirection: Axis.horizontal,
              itemCount: BookingStatusFilter.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: Spacing.xs),
              itemBuilder: (context, i) {
                final f = BookingStatusFilter.values[i];
                return ChoiceChip(
                  label: Text(_filterLabel(f)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Expanded(
            child: AsyncView(
              value: bookingsAsync,
              onRetry: () => ref.invalidate(allBookingsProvider),
              data: (all) {
                final bookings = filterBookings(all, _filter)
                    .where((r) => bookingMatchesSearch(r, _search))
                    .toList();
                if (bookings.isEmpty) {
                  // The exact string (including the trailing period) is
                  // asserted verbatim by admin_bookings_screen_test.dart.
                  return const EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No bookings match this filter.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      Spacing.md, 0, Spacing.md, Spacing.md),
                  itemCount: bookings.length,
                  itemBuilder: (context, i) {
                    final reservation = bookings[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: AdminBookingCard(
                        reservation: reservation,
                        onTap: () =>
                            context.push('/booking-detail/${reservation.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One reservation row, styled after the mockup's booking card: code +
/// status pill, guest name, date range with night count, guest count,
/// amount, and when the booking was made.
class AdminBookingCard extends StatelessWidget {
  const AdminBookingCard({super.key, required this.reservation, this.onTap});

  final Reservation reservation;
  final VoidCallback? onTap;

  static String statusLabel(ReservationStatus status) => switch (status) {
        ReservationStatus.hold => 'Pending',
        ReservationStatus.pendingPayment => 'Pending',
        ReservationStatus.confirmed => 'Confirmed',
        ReservationStatus.checkedIn => 'Confirmed',
        ReservationStatus.checkedOut => 'Completed',
        ReservationStatus.cancelled => 'Cancelled',
      };

  /// The status pill's tint -- distinct colours per the mockup so the
  /// admin can tell a card's state apart at a glance, without reading it.
  (Color background, Color foreground) _statusColors(ColorScheme scheme) =>
      switch (reservation.status) {
        ReservationStatus.confirmed ||
        ReservationStatus.checkedIn =>
          (scheme.primaryContainer, scheme.onPrimaryContainer),
        ReservationStatus.checkedOut =>
          (scheme.secondaryContainer, scheme.onSecondaryContainer),
        ReservationStatus.cancelled =>
          (scheme.errorContainer, scheme.onErrorContainer),
        ReservationStatus.hold ||
        ReservationStatus.pendingPayment =>
          (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      };

  // `end.difference(start).inDays` truncates the raw duration -- a 2pm
  // check-in to an 11am check-out next day is ~21 hours, so a genuine
  // 1-night stay reported "0 Nights" (and a 2-night stay "1 Night"), for
  // every booking in this list. Reproduced live: a Sep 7 -> Sep 8 booking
  // showed "(0 Nights)". Counting the gap between local CALENDAR dates
  // instead -- the same date-based approach `report_occupancy` already
  // uses server-side -- matches the nights actually billed.
  int get _nights {
    final start = reservation.start.toLocal();
    final end = reservation.end.toLocal();
    return DateTime(end.year, end.month, end.day)
        .difference(DateTime(start.year, start.month, start.day))
        .inDays;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (background, foreground) = _statusColors(scheme);
    final nights = _nights;
    final createdAt = reservation.createdAt?.toLocal();

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PasalaTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(bookingCode(reservation.id),
                      style: textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel(reservation.status),
                      style: textTheme.labelMedium?.copyWith(color: foreground),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(reservation.customerName ?? 'Guest',
                  style: textTheme.bodyLarge),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      '${formatDay(reservation.start.toLocal())} - '
                      '${formatDay(reservation.end.toLocal())} '
                      '($nights ${nights == 1 ? 'Night' : 'Nights'})',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                children: [
                  Icon(Icons.people_alt_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    '${reservation.guests ?? 0} Guests',
                    style: textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (reservation.quote != null)
                    Text(
                      formatInr(reservation.quote!.total),
                      style: textTheme.titleMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (createdAt != null) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  'Created ${formatDate(createdAt)} at '
                  '${DateFormat.jm().format(createdAt)}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/coupon.dart';
import '../../data/repositories/coupon_repository.dart';
import 'coupon_form.dart';

/// `/admin/coupons` -- the current resort's coupons, for its owner and
/// admins (`redirectFor`'s `/admin/*` rule; `list_coupons` and the write
/// functions assert the same roles in Postgres). Lists every coupon with
/// its status, discount, dates, usage and audience. Tapping a card edits
/// it; the button on each card deactivates (after a confirmation) or
/// reactivates it. There is no delete: a coupon's history stays.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final propertyId = ref.watch(currentResortProvider)?.propertyId;
    if (propertyId == null) {
      // The router only sends an owner or admin (who always has a current
      // resort) here; this covers the moment right after sign-out.
      return const Scaffold(body: SizedBox.shrink());
    }
    final couponsAsync = ref.watch(couponsProvider(propertyId));
    Future<void> refresh() => ref.refresh(couponsProvider(propertyId).future);

    return Scaffold(
      appBar: AppBar(title: const Text('Coupons')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-coupon'),
        onPressed: () => _openForm(context, ref, propertyId),
        icon: const Icon(Icons.add),
        label: const Text('New coupon'),
      ),
      body: AsyncView(
        value: couponsAsync,
        onRetry: () => ref.invalidate(couponsProvider(propertyId)),
        empty: () => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              EmptyState(
                icon: Icons.local_offer_outlined,
                title: 'No coupons yet',
                message: 'Create a code guests can enter when they book.',
              ),
            ],
          ),
        ),
        data: (coupons) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            // Bottom padding keeps the last card clear of the button.
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.md, Spacing.md, 96),
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
            itemBuilder: (context, i) => CouponTile(
              coupon: coupons[i],
              onEdit: () =>
                  _openForm(context, ref, propertyId, coupon: coupons[i]),
              onToggleActive: () =>
                  _toggle(context, ref, propertyId, coupons[i]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    String propertyId, {
    Coupon? coupon,
  }) async {
    final saved = await showCouponForm(
      context,
      propertyId: propertyId,
      coupon: coupon,
    );
    if (!saved || !context.mounted) return;
    ref.invalidate(couponsProvider(propertyId));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(coupon == null ? 'Coupon created' : 'Coupon saved'),
    ));
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    String propertyId,
    Coupon coupon,
  ) async {
    final activate = !coupon.isActive;
    if (!activate) {
      final confirmed = await showDialog<bool>(
        context: context,
        // The buttons pop with the dialog's own context: this screen lives
        // in the router's ShellRoute, so its context would pop the page.
        builder: (dialogContext) => AlertDialog(
          title: Text('Deactivate ${coupon.code}?'),
          content: const Text(
            'Guests can no longer apply it. Bookings that already used it '
            'keep their discount.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(couponSourceProvider).setActive(coupon.id, activate);
      ref.invalidate(couponsProvider(propertyId));
      messenger.showSnackBar(SnackBar(
        content: Text(activate
            ? '${coupon.code} is active again'
            : '${coupon.code} deactivated'),
      ));
    } on BookingFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// One coupon: code and status on top, then discount and minimum, dates,
/// and usage with audience, and the Deactivate/Activate button.
class CouponTile extends StatelessWidget {
  const CouponTile({
    super.key,
    required this.coupon,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Coupon coupon;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final discount = [
      coupon.discountLabel,
      if (coupon.minAmountLabel != null) coupon.minAmountLabel!,
    ].join(' · ');

    return Card(
      key: Key('coupon-tile-${coupon.id}'),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Spacing.md, Spacing.md, Spacing.md, Spacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      coupon.code,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  CouponStatusChip(status: coupon.status),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(discount, style: textTheme.bodyLarge),
              Text(coupon.validityLabel, style: muted),
              Text('${coupon.usageLabel} · ${coupon.audienceLabel}',
                  style: muted),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: Key('coupon-toggle-${coupon.id}'),
                  onPressed: onToggleActive,
                  child: Text(coupon.isActive ? 'Deactivate' : 'Activate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A coupon's status as icon plus label on a tinted pill -- never colour
/// alone.
class CouponStatusChip extends StatelessWidget {
  const CouponStatusChip({super.key, required this.status});

  final CouponStatus status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 2),
    decoration: BoxDecoration(
      color: status.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 16, color: status.color),
        const SizedBox(width: Spacing.xs),
        Text(
          status.label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: status.color),
        ),
      ],
    ),
  );
}

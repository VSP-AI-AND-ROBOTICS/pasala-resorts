import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/current_resort.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/listing.dart';
import '../../data/models/subscription.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/listing_repository.dart';
import '../../data/repositories/platform_repository.dart';

/// Makes [propertyId] -- a resort the user has just applied for, or is
/// still setting up -- the current resort and opens `/owner`, where the
/// setup checklist is. The user is refetched first, because the owner
/// membership was created on the server a moment ago.
///
/// Uses the router and the container captured up front, not the calling
/// widget: selecting the resort rebuilds the shell's navigator, which can
/// dispose that widget before the navigation.
Future<void> openListedResort(BuildContext context, String propertyId) async {
  final router = GoRouter.of(context);
  final container = ProviderScope.containerOf(context);
  // Riverpod 3 auto-disposes an unlistened provider before its stream
  // emits; a subscription that outlives this function (the widget tree
  // that watches it in the real app) keeps it alive long enough here too.
  final sub = container.listen(currentUserProvider, (_, _) {});
  try {
    container.invalidate(currentUserProvider);
    await container.read(currentUserProvider.future);
    await container.read(currentResortProvider.notifier).select(propertyId);
    router.go('/owner');
  } finally {
    sub.close();
  }
}

/// `/list-your-resort` (P10): a signed-in user applies to list a resort.
/// With an open application (one per user) it shows that application and
/// "Continue setup" instead of the form; decided applications are listed
/// below, a rejection with its reason.
class ListYourResortScreen extends ConsumerWidget {
  const ListYourResortScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(myListingApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('List your resort')),
      body: AsyncView(
        value: applications,
        onRetry: () => ref.invalidate(myListingApplicationsProvider),
        data: (apps) {
          final open = apps.where((a) => a.isOpen);
          final earlier = apps.where((a) => !a.isOpen).toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(Spacing.md),
                children: [
                  if (open.isNotEmpty)
                    _OpenApplicationCard(application: open.first)
                  else
                    const ListingForm(),
                  if (earlier.isNotEmpty) ...[
                    const SizedBox(height: Spacing.lg),
                    Text('Earlier applications',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: Spacing.sm),
                    for (final a in earlier)
                      Card(
                        key: Key('listing-history-${a.propertyId}'),
                        child: ListTile(
                          title: Text(a.name),
                          subtitle: Text(a.statusLine),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OpenApplicationCard extends StatelessWidget {
  const _OpenApplicationCard({required this.application});

  final ListingApplication application;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      key: const Key('listing-open'),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(application.name, style: textTheme.titleMedium),
            const SizedBox(height: Spacing.xs),
            Text('${application.city} · ${application.tier.label} plan'),
            const SizedBox(height: Spacing.xs),
            Text(application.statusLine,
                style: textTheme.bodyMedium?.copyWith(color: scheme.primary)),
            const SizedBox(height: Spacing.md),
            FilledButton(
              key: const Key('listing-continue'),
              onPressed: () =>
                  openListedResort(context, application.propertyId),
              child: const Text('Continue setup'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The application form. It checks the same rules as `apply_for_listing`
/// before sending, and disables Apply while the call runs, so a double
/// tap sends one application.
class ListingForm extends ConsumerStatefulWidget {
  const ListingForm({super.key});

  @override
  ConsumerState<ListingForm> createState() => _ListingFormState();
}

class _ListingFormState extends ConsumerState<ListingForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  SubscriptionTier _tier = SubscriptionTier.starter;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _phone.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(listingSourceProvider).apply(ListingInput(
            name: _name.text,
            city: _city.text,
            address: _address.text,
            contactPhone: _phone.text,
            description: _description.text,
            tier: _tier,
          ));
      if (!mounted) return;
      await openListedResort(context, id);
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
  Widget build(BuildContext context) {
    final plans =
        ref.watch(subscriptionPlansProvider).value ?? const <SubscriptionPlan>[];
    final prices = {for (final p in plans) p.tier: p.monthlyPriceInr};
    String tierLabel(SubscriptionTier t) => prices[t] == null
        ? t.label
        : '${t.label} — ${formatInr(prices[t]!)}/month';

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Tell us about your resort. It stays hidden from guests until '
            'ResortHub approves it.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.md),
          TextFormField(
            key: const Key('listing-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Resort name'),
            textInputAction: TextInputAction.next,
            validator: validateListingName,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-city'),
            controller: _city,
            decoration: const InputDecoration(labelText: 'City'),
            textInputAction: TextInputAction.next,
            validator: validateListingCity,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-address'),
            controller: _address,
            decoration: const InputDecoration(labelText: 'Address'),
            minLines: 1,
            maxLines: 3,
            validator: validateListingAddress,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-phone'),
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Contact phone'),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: validateListingPhone,
          ),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            key: const Key('listing-description'),
            controller: _description,
            decoration: const InputDecoration(labelText: 'Short description'),
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            validator: validateListingDescription,
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<SubscriptionTier>(
            key: const Key('listing-tier'),
            initialValue: _tier,
            decoration: const InputDecoration(labelText: 'Plan'),
            items: [
              for (final t in SubscriptionTier.values)
                DropdownMenuItem(value: t, child: Text(tierLabel(t))),
            ],
            onChanged: (t) => setState(() => _tier = t ?? _tier),
          ),
          const SizedBox(height: Spacing.xs),
          const Text('30-day free trial. No payment needed now.'),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            key: const Key('listing-submit'),
            onPressed: _busy ? null : _submit,
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

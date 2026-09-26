import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

const _availableMethods = ['UPI', 'Card', 'Net Banking', 'Wallet'];

/// Payment configuration -- business-facing settings only. Razorpay keys
/// are Edge Function secrets set at deploy time (README, "Online payments
/// (Razorpay)") and are never in the app, the database, or editable
/// here -- this screen controls `properties.advance_pct` (already existed,
/// previously psql-only) plus the two purely-cosmetic
/// `payment_display_methods`/`gateway_display_name` columns
/// (`0025_property_settings.sql`).
class PaymentSettingsScreen extends ConsumerStatefulWidget {
  const PaymentSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<PaymentSettingsScreen> createState() =>
      _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends ConsumerState<PaymentSettingsScreen> {
  late final TextEditingController _advancePct;
  late final TextEditingController _gatewayName;
  late Set<String> _methods;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _advancePct = TextEditingController(text: '${widget.property.advancePct}');
    _gatewayName = TextEditingController(text: widget.property.gatewayDisplayName ?? '');
    _methods = widget.property.paymentDisplayMethods.toSet();
  }

  @override
  void dispose() {
    _advancePct.dispose();
    _gatewayName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final advancePct = num.tryParse(_advancePct.text.trim());
    if (advancePct == null || advancePct <= 0 || advancePct > 100) {
      setState(() => _error = 'Enter an advance percentage between 1 and 100.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gatewayName = _gatewayName.text.trim();
      await ref.read(catalogRepositoryProvider).updateSettings(widget.property.id, {
        'advance_pct': advancePct,
        'payment_display_methods': _methods.toList(),
        'gateway_display_name': gatewayName.isEmpty ? null : gatewayName,
      });
      ref.invalidate(propertiesProvider);
      ref.invalidate(propertyProvider(widget.property.id));
      if (mounted) Navigator.of(context).pop();
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
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment configuration')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Padding(
                    padding: EdgeInsets.all(Spacing.md),
                    child: Text(
                      'Gateway credentials are configured at deploy time and are '
                      'never stored here. This screen only controls what customers '
                      'see and how much of a booking must be paid up front.',
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.md),
                TextField(
                  key: const Key('payment-advance-pct-field'),
                  controller: _advancePct,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Advance payment required (%)',
                    helperText: 'Minimum share of the total due to confirm a booking',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text('Payment methods shown to customers',
                    style: Theme.of(context).textTheme.labelLarge),
                for (final method in _availableMethods)
                  CheckboxListTile(
                    key: Key('payment-method-$method'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(method),
                    value: _methods.contains(method),
                    onChanged: (checked) => setState(() {
                      if (checked ?? false) {
                        _methods.add(method);
                      } else {
                        _methods.remove(method);
                      }
                    }),
                  ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('payment-gateway-name-field'),
                  controller: _gatewayName,
                  decoration: const InputDecoration(
                    labelText: 'Gateway display name',
                    helperText: 'Optional, e.g. "Secured by Razorpay"',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.sm),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: Spacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Taxes -- the room rate and GSTIN (`0025_property_settings.sql`) and the
/// food & drink and spa & activities rates (`0053_food_spa_tax.sql`).
///
/// The room rate changes real pricing: `get_quote` adds it on top of the
/// room subtotal, so a booking made after a nonzero rate is saved costs
/// more. The food and spa rates change no price -- menu and activity prices
/// already include them -- they decide how much of each new order or sale
/// is recorded as tax. Every order and sale keeps the rate it was made at.
class TaxSettingsScreen extends ConsumerStatefulWidget {
  const TaxSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends ConsumerState<TaxSettingsScreen> {
  late final TextEditingController _taxPct;
  late final TextEditingController _fnbPct;
  late final TextEditingController _spaPct;
  late final TextEditingController _gstin;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _taxPct = TextEditingController(text: formatPct(widget.property.taxPct));
    _fnbPct = TextEditingController(text: formatPct(widget.property.fnbTaxPct));
    _spaPct = TextEditingController(text: formatPct(widget.property.spaTaxPct));
    _gstin = TextEditingController(text: widget.property.gstin ?? '');
  }

  @override
  void dispose() {
    _taxPct.dispose();
    _fnbPct.dispose();
    _spaPct.dispose();
    _gstin.dispose();
    super.dispose();
  }

  /// The rate typed into [controller], or null (with [message] shown) when
  /// it is not a finite number from 0 to [max]. `num.tryParse` accepts
  /// `NaN`, which passes both range comparisons, hence `isFinite`.
  num? _rate(TextEditingController controller, num max, String message) {
    final value = num.tryParse(controller.text.trim());
    if (value == null || !value.isFinite || value < 0 || value > max) {
      setState(() => _error = message);
      return null;
    }
    return value;
  }

  Future<void> _save() async {
    final taxPct = _rate(_taxPct, 100, 'Enter a room tax rate between 0 and 100.');
    if (taxPct == null) return;
    final fnbPct = _rate(_fnbPct, 28, 'Enter a food & drink tax rate between 0 and 28.');
    if (fnbPct == null) return;
    final spaPct = _rate(_spaPct, 28, 'Enter a spa & activities tax rate between 0 and 28.');
    if (spaPct == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gstin = _gstin.text.trim();
      await ref.read(catalogRepositoryProvider).updateSettings(widget.property.id, {
        'tax_pct': taxPct,
        'fnb_tax_pct': fnbPct,
        'spa_tax_pct': spaPct,
        'gstin': gstin.isEmpty ? null : gstin,
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

  Widget _rateField(String key, TextEditingController controller, String label,
          String helper) =>
      TextField(
        key: Key(key),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, helperText: helper),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Taxes')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                _rateField('tax-pct-field', _taxPct, 'Room tax rate (%)',
                    'Added on top of the room price at booking time'),
                const SizedBox(height: Spacing.sm),
                _rateField('tax-fnb-field', _fnbPct, 'Food & drink tax (%)',
                    'Already included in menu prices'),
                const SizedBox(height: Spacing.sm),
                _rateField('tax-spa-field', _spaPct, 'Spa & activities tax (%)',
                    'Already included in activity prices'),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('tax-gstin-field'),
                  controller: _gstin,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    helperText: 'Optional',
                  ),
                ),
                const SizedBox(height: Spacing.md),
                Text(
                  'Each order and sale keeps the rate it was made at. '
                  'Changing a rate affects new sales only.',
                  key: const Key('tax-inclusive-note'),
                  style: Theme.of(context).textTheme.bodySmall,
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

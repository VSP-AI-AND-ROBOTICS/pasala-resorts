import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Taxes -- `properties.tax_pct`/`gstin` (`0025_property_settings.sql`).
/// Saving here changes real pricing: `get_quote` adds `tax_pct` as its own
/// additive line on top of the coupon-discounted subtotal, so a booking
/// made after this screen saves a nonzero rate genuinely costs more.
class TaxSettingsScreen extends ConsumerStatefulWidget {
  const TaxSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends ConsumerState<TaxSettingsScreen> {
  late final TextEditingController _taxPct;
  late final TextEditingController _gstin;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _taxPct = TextEditingController(text: '${widget.property.taxPct}');
    _gstin = TextEditingController(text: widget.property.gstin ?? '');
  }

  @override
  void dispose() {
    _taxPct.dispose();
    _gstin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final taxPct = num.tryParse(_taxPct.text.trim());
    if (taxPct == null || taxPct < 0 || taxPct > 100) {
      setState(() => _error = 'Enter a tax rate between 0 and 100.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final gstin = _gstin.text.trim();
      await ref.read(catalogRepositoryProvider).updateSettings(widget.property.id, {
        'tax_pct': taxPct,
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
                TextField(
                  key: const Key('tax-pct-field'),
                  controller: _taxPct,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tax rate (%)',
                    helperText: 'Added on top of the quoted total at booking time',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('tax-gstin-field'),
                  controller: _gstin,
                  decoration: const InputDecoration(
                    labelText: 'GSTIN',
                    helperText: 'Optional',
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

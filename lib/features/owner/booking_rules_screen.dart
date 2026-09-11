import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Booking rules -- `properties.min_nights`/`max_nights`
/// (`0025_property_settings.sql`), enforced inside `get_quote` for nightly
/// bookings only (a slot booking has no "nights" to limit). Leaving either
/// field blank means "no limit," matching the columns' nullable, opt-in
/// design -- a property that never visits this screen keeps accepting any
/// stay length, exactly as before this feature existed.
class BookingRulesScreen extends ConsumerStatefulWidget {
  const BookingRulesScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<BookingRulesScreen> createState() => _BookingRulesScreenState();
}

class _BookingRulesScreenState extends ConsumerState<BookingRulesScreen> {
  late final TextEditingController _minNights;
  late final TextEditingController _maxNights;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _minNights = TextEditingController(
      text: widget.property.minNights?.toString() ?? '',
    );
    _maxNights = TextEditingController(
      text: widget.property.maxNights?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _minNights.dispose();
    _maxNights.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minText = _minNights.text.trim();
    final maxText = _maxNights.text.trim();
    final min = minText.isEmpty ? null : int.tryParse(minText);
    final max = maxText.isEmpty ? null : int.tryParse(maxText);
    if ((minText.isNotEmpty && (min == null || min <= 0)) ||
        (maxText.isNotEmpty && (max == null || max <= 0))) {
      setState(() => _error = 'Enter whole numbers greater than zero, or leave blank.');
      return;
    }
    if (min != null && max != null && max < min) {
      setState(() => _error = 'Maximum nights cannot be less than minimum nights.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).updateSettings(widget.property.id, {
        'min_nights': min,
        'max_nights': max,
      });
      ref.invalidate(propertiesProvider);
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
        appBar: AppBar(title: const Text('Booking rules')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Spacing.lg),
              children: [
                TextField(
                  key: const Key('booking-rules-min-nights-field'),
                  controller: _minNights,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Minimum nights',
                    helperText: 'Leave blank for no minimum',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextField(
                  key: const Key('booking-rules-max-nights-field'),
                  controller: _maxNights,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Maximum nights',
                    helperText: 'Leave blank for no maximum',
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

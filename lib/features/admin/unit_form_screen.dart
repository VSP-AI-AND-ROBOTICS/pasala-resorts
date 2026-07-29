import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../data/models/unit.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Label for a [BookingMode] segment. Kept here (rather than reusing
/// `bookingModeLabel` from `property_screen.dart`) because that one is
/// customer-facing copy ("Nightly or slots") and this admin control needs
/// the shorter segmented-button labels.
String _modeSegmentLabel(BookingMode mode) => switch (mode) {
      BookingMode.nightly => 'Nightly',
      BookingMode.slot => 'Slot',
      BookingMode.both => 'Both',
    };

/// Create/edit form for a [Unit]. A unit created here has no rate rule yet --
/// `quote_reservation` (P0004) refuses to price a unit with no base rate --
/// so a successful *create* (never an edit) shows a prompt and hands the
/// admin straight to the rates screen for that unit.
class UnitFormScreen extends ConsumerStatefulWidget {
  const UnitFormScreen({super.key, required this.propertyId, this.existing});

  final String propertyId;
  final Unit? existing;

  @override
  ConsumerState<UnitFormScreen> createState() => _UnitFormScreenState();
}

class _UnitFormScreenState extends ConsumerState<UnitFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _capacityBase;
  late final TextEditingController _capacityMax;
  late BookingMode _bookingMode;
  late bool _isActive;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _capacityBase =
        TextEditingController(text: existing?.capacityBase.toString() ?? '');
    _capacityMax =
        TextEditingController(text: existing?.capacityMax.toString() ?? '');
    _bookingMode = existing?.bookingMode ?? BookingMode.nightly;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _capacityBase.dispose();
    _capacityMax.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final unit = Unit(
        id: existing?.id ?? '',
        propertyId: widget.propertyId,
        name: _name.text.trim(),
        description: existing?.description,
        capacityBase: int.parse(_capacityBase.text),
        capacityMax: int.parse(_capacityMax.text),
        bookingMode: _bookingMode,
        isActive: _isActive,
      );
      final created = await ref
          .read(catalogRepositoryProvider)
          .upsertUnit(unit, id: existing?.id);
      ref.invalidate(unitsProvider(widget.propertyId));
      if (!mounted) return;

      final isNew = existing == null;
      if (isNew) {
        // A unit with no base rate rule can't be quoted (P0004), so a
        // successful create hands the admin straight to the rates screen
        // instead of just popping back to the unit list. `context.go`
        // replaces the current location outright, which also clears this
        // pushed form off the stack -- no separate pop needed.
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Unit created. Add a base rate before it can be booked.'),
        ));
        context.go('/admin/rates/${created.id}');
      } else {
        Navigator.of(context).pop();
      }
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New unit' : 'Edit unit'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  TextFormField(
                    key: const Key('unit-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('unit-capacity-base'),
                    controller: _capacityBase,
                    decoration:
                        const InputDecoration(labelText: 'Base capacity'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final base = int.tryParse(v ?? '');
                      if (base == null || base < 1) return 'Enter a number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('unit-capacity-max'),
                    controller: _capacityMax,
                    decoration:
                        const InputDecoration(labelText: 'Max capacity'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final max = int.tryParse(v ?? '');
                      final base = int.tryParse(_capacityBase.text);
                      if (max == null || max < 1) return 'Enter a number';
                      if (base != null && max < base) {
                        return 'Max must be at least the base capacity';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<BookingMode>(
                    segments: [
                      for (final mode in BookingMode.values)
                        ButtonSegment(
                          value: mode,
                          label: Text(_modeSegmentLabel(mode)),
                        ),
                    ],
                    selected: {_bookingMode},
                    onSelectionChanged: (selection) =>
                        setState(() => _bookingMode = selection.first),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    key: const Key('unit-active'),
                    title: const Text('Active'),
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

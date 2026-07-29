import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/browse_screen.dart' show PropertyCard;
import '../browse/providers.dart';

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Parses a `Property.checkInTime`/`checkOutTime` string (already normalized
/// to `HH:mm` by `Property.fromJson`) into a [TimeOfDay] for `showTimePicker`
/// to edit. Runs [Property.normalizeTime] again first purely as a defensive
/// measure -- this is the one place a raw `HH:mm:ss` would otherwise crash
/// `int.parse` on the seconds component instead of just displaying wrong.
TimeOfDay _parseTime(String raw) {
  final parts = Property.normalizeTime(raw).split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

/// Create/edit form for a [Property]. Pushed imperatively (via
/// `Navigator.push`) from `AdminPropertiesScreen` rather than routed, since
/// there is no dedicated `/admin/properties/...` route for it.
class PropertyFormScreen extends ConsumerStatefulWidget {
  const PropertyFormScreen({super.key, this.existing});

  final Property? existing;

  @override
  ConsumerState<PropertyFormScreen> createState() =>
      _PropertyFormScreenState();
}

class _PropertyFormScreenState extends ConsumerState<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _slug;
  late final TextEditingController _description;
  late final TextEditingController _address;
  late final TextEditingController _amenities;
  late TimeOfDay _checkInTime;
  late TimeOfDay _checkOutTime;
  late bool _isActive;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _slug = TextEditingController(text: existing?.slug ?? '');
    _description = TextEditingController(text: existing?.description ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
    _amenities =
        TextEditingController(text: existing?.amenities.join(', ') ?? '');
    _checkInTime = _parseTime(existing?.checkInTime ?? '14:00');
    _checkOutTime = _parseTime(existing?.checkOutTime ?? '11:00');
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _description.dispose();
    _address.dispose();
    _amenities.dispose();
    super.dispose();
  }

  Future<void> _pickCheckIn() async {
    final picked =
        await showTimePicker(context: context, initialTime: _checkInTime);
    if (picked != null) setState(() => _checkInTime = picked);
  }

  Future<void> _pickCheckOut() async {
    final picked =
        await showTimePicker(context: context, initialTime: _checkOutTime);
    if (picked != null) setState(() => _checkOutTime = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final existing = widget.existing;
      final description = _description.text.trim();
      final address = _address.text.trim();
      final property = Property(
        id: existing?.id ?? '',
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        description: description.isEmpty ? null : description,
        address: address.isEmpty ? null : address,
        images: existing?.images ?? const [],
        amenities: _amenities.text
            .split(',')
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList(),
        checkInTime: _formatTimeOfDay(_checkInTime),
        checkOutTime: _formatTimeOfDay(_checkOutTime),
        isActive: _isActive,
      );
      await ref
          .read(catalogRepositoryProvider)
          .upsertProperty(property, id: existing?.id);
      ref.invalidate(propertiesProvider);
      if (mounted) Navigator.of(context).pop();
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
          title:
              Text(widget.existing == null ? 'New property' : 'Edit property'),
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
                    key: const Key('property-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('property-slug'),
                    controller: _slug,
                    decoration: const InputDecoration(labelText: 'Slug'),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter a slug'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('property-description'),
                    controller: _description,
                    decoration:
                        const InputDecoration(labelText: 'Description'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('property-address'),
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'Address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('property-amenities'),
                    controller: _amenities,
                    decoration: const InputDecoration(
                      labelText: 'Amenities',
                      helperText: 'Comma-separated, e.g. Pool, Wi-Fi',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check-in time'),
                    trailing: Text(_formatTimeOfDay(_checkInTime)),
                    onTap: _pickCheckIn,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Check-out time'),
                    trailing: Text(_formatTimeOfDay(_checkOutTime)),
                    onTap: _pickCheckOut,
                  ),
                  SwitchListTile(
                    key: const Key('property-active'),
                    contentPadding: EdgeInsets.zero,
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

/// Admin's property list at `/admin/properties`, reusing `PropertyCard` from
/// the customer browse screen. Tapping a card manages its units; the edit
/// button opens `PropertyFormScreen` for that property.
class AdminPropertiesScreen extends ConsumerWidget {
  const AdminPropertiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(propertiesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(propertiesProvider),
        ),
        data: (list) => ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final property = list[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PropertyCard(
                      property: property,
                      onTap: () => context.go('/admin/units/${property.id}'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PropertyFormScreen(existing: property),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PropertyFormScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

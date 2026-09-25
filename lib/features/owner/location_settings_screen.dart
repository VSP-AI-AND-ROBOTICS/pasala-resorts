import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/location/geo_point.dart';
import '../../core/location/position_service.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/property.dart';
import '../../data/repositories/catalog_repository.dart';
import '../browse/providers.dart';

/// Validates the Map location form. Both fields empty clears the location
/// (`point` and `error` both null). Anything else must be a valid pair;
/// otherwise `error` says what is wrong. The table's
/// `properties_coordinates_pair` and range checks (0060) are the backstop.
({GeoPoint? point, String? error}) parseCoordinates(
    String latText, String lngText) {
  final lat = latText.trim();
  final lng = lngText.trim();
  if (lat.isEmpty && lng.isEmpty) return (point: null, error: null);
  if (lat.isEmpty || lng.isEmpty) {
    return (
      point: null,
      error: 'Enter both latitude and longitude, or leave both empty.',
    );
  }
  final latitude = double.tryParse(lat);
  final longitude = double.tryParse(lng);
  if (latitude == null || longitude == null) {
    return (
      point: null,
      error: 'Latitude and longitude must be numbers, like 17.385 and 78.4867.',
    );
  }
  final point = GeoPoint(latitude, longitude);
  if (!point.isValid) {
    return (
      point: null,
      error: 'Latitude must be between -90 and 90, '
          'and longitude between -180 and 180.',
    );
  }
  return (point: point, error: null);
}

/// Map location: `properties.lat`/`lng`, pushed from Owner Settings.
/// Guests see the distance to these coordinates and can sort by it. The
/// save goes through the existing `properties_update` policy (owner or
/// admin; a suspended resort refuses with P0022), the same way the Tax and
/// Booking-rules screens save.
class LocationSettingsScreen extends ConsumerStatefulWidget {
  const LocationSettingsScreen({super.key, required this.property});

  final Property property;

  @override
  ConsumerState<LocationSettingsScreen> createState() =>
      _LocationSettingsScreenState();
}

class _LocationSettingsScreenState
    extends ConsumerState<LocationSettingsScreen> {
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  String? _error;
  bool _busy = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(
        text: widget.property.latitude?.toStringAsFixed(6) ?? '');
    _lng = TextEditingController(
        text: widget.property.longitude?.toStringAsFixed(6) ?? '');
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final point = await ref.read(positionServiceProvider).precisePosition();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (point == null) {
        _error = 'Could not get your location. '
            'Allow location access, or type the coordinates.';
      } else {
        _lat.text = point.latitude.toStringAsFixed(6);
        _lng.text = point.longitude.toStringAsFixed(6);
      }
    });
  }

  Future<void> _save() async {
    final parsed = parseCoordinates(_lat.text, _lng.text);
    if (parsed.error != null) {
      setState(() => _error = parsed.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).updateSettings(
        widget.property.id,
        {'lat': parsed.point?.latitude, 'lng': parsed.point?.longitude},
      );
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Map location')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              Text(
                'Guests see how far away you are and can sort resorts by '
                'distance. Leave both fields empty to hide your distance.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                key: const Key('location-use-current'),
                onPressed: _locating || _busy ? null : _useCurrentLocation,
                icon: _locating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: const Text('Use my current location'),
              ),
              const SizedBox(height: Spacing.md),
              TextField(
                key: const Key('location-lat'),
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  helperText: 'Between -90 and 90, e.g. 17.385044',
                ),
              ),
              const SizedBox(height: Spacing.sm),
              TextField(
                key: const Key('location-lng'),
                controller: _lng,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  helperText: 'Between -180 and 180, e.g. 78.486671',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                key: const Key('location-save'),
                onPressed: _busy ? null : _save,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

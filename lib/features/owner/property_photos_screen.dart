import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/property_photos_repository.dart';
import '../browse/providers.dart';

/// A photo chosen on the device, ready to upload.
typedef PickedPhoto = ({String filename, Uint8List bytes, String contentType});

/// Opens the device gallery (a file picker on the web); null when the
/// owner cancels. Large photos are scaled down before upload.
Future<PickedPhoto?> pickPhotoFromGallery() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    imageQuality: 85,
  );
  if (file == null) return null;
  return (
    filename: file.name,
    bytes: await file.readAsBytes(),
    contentType: file.mimeType ?? 'image/jpeg',
  );
}

/// Photos -- the pictures guests see on the listing (`properties.images`,
/// P10 spec decision 17). Reached from the setup checklist and from
/// Settings. Uploads go to the public `property-photos` bucket; removing a
/// photo only drops its URL.
class PropertyPhotosScreen extends ConsumerStatefulWidget {
  const PropertyPhotosScreen({
    super.key,
    required this.propertyId,
    this.pickPhoto,
  });

  final String propertyId;

  /// Tests pass a fake; the app uses [pickPhotoFromGallery].
  final Future<PickedPhoto?> Function()? pickPhoto;

  @override
  ConsumerState<PropertyPhotosScreen> createState() =>
      _PropertyPhotosScreenState();
}

class _PropertyPhotosScreenState extends ConsumerState<PropertyPhotosScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
      ref.invalidate(propertyProvider(widget.propertyId));
      ref.invalidate(propertiesProvider);
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add(List<String> current) async {
    final photo = await (widget.pickPhoto ?? pickPhotoFromGallery)();
    if (photo == null || !mounted) return;
    await _run(() async {
      final source = ref.read(propertyPhotosSourceProvider);
      final url = await source.upload(
        widget.propertyId,
        filename: photo.filename,
        bytes: photo.bytes,
        contentType: photo.contentType,
      );
      await source.setPhotos(widget.propertyId, [...current, url]);
    });
  }

  Future<void> _remove(List<String> current, int index) => _run(
        () => ref
            .read(propertyPhotosSourceProvider)
            .setPhotos(widget.propertyId, [...current]..removeAt(index)),
      );

  @override
  Widget build(BuildContext context) {
    final property = ref.watch(propertyProvider(widget.propertyId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      body: AsyncView(
        value: property,
        onRetry: () => ref.invalidate(propertyProvider(widget.propertyId)),
        data: (p) {
          final images = p.images;
          final full = images.length >= maxPropertyPhotos;
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              if (images.isEmpty)
                const Padding(
                  key: Key('photos-empty'),
                  padding: EdgeInsets.all(Spacing.lg),
                  child: Text('No photos yet', textAlign: TextAlign.center),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisSpacing: Spacing.sm,
                    crossAxisSpacing: Spacing.sm,
                    childAspectRatio: 4 / 3,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, i) => Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(PasalaTokens.radiusSm),
                        child: Image.network(
                          images[i],
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo ${i + 1} of ${images.length}',
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: Spacing.xs,
                        right: Spacing.xs,
                        child: IconButton.filledTonal(
                          key: Key('photo-remove-$i'),
                          tooltip: 'Remove photo',
                          icon: const Icon(Icons.delete_outline),
                          onPressed:
                              _busy ? null : () => _remove(images, i),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Spacing.md),
              FilledButton.icon(
                key: const Key('add-photo'),
                onPressed: _busy || full ? null : () => _add(images),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add photo'),
              ),
              if (full) ...[
                const SizedBox(height: Spacing.xs),
                const Text('You can add up to 10 photos.',
                    textAlign: TextAlign.center),
              ],
            ],
          );
        },
      ),
    );
  }
}

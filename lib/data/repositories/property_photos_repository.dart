import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';

/// The public Storage bucket for listing photos (0059). Objects live at
/// `{property_id}/{file}`; only the resort's owners and admins may write.
const propertyPhotosBucket = 'property-photos';

/// The Photos screen stops offering "Add photo" at this many.
const maxPropertyPhotos = 10;

/// Tests override [propertyPhotosSourceProvider] with
/// `FakePropertyPhotosSource` (test/support/fake_property_photos_source.dart).
abstract class PropertyPhotosSource {
  /// Uploads one photo for [propertyId] and returns its public URL.
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  });

  /// Replaces `properties.images` with [urls], in order.
  Future<void> setPhotos(String propertyId, List<String> urls);
}

class PropertyPhotosRepository implements PropertyPhotosSource {
  PropertyPhotosRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  @override
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) => _guard(() async {
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$propertyId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    final bucket = _db.storage.from(propertyPhotosBucket);
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType),
    );
    return bucket.getPublicUrl(path);
  });

  @override
  Future<void> setPhotos(String propertyId, List<String> urls) =>
      _guard(() async {
        await _db
            .from('properties')
            .update({'images': urls})
            .eq('id', propertyId);
      });
}

final propertyPhotosSourceProvider = Provider<PropertyPhotosSource>(
  (ref) => PropertyPhotosRepository(ref.watch(supabaseProvider)),
);

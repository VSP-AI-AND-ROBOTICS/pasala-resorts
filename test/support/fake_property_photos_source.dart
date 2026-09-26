import 'dart:typed_data';

import 'package:pasala/data/repositories/property_photos_repository.dart';

/// In-memory [PropertyPhotosSource]. `upload` returns [nextUrl] and logs
/// `(propertyId, filename, byte count)`; `setPhotos` logs the full list.
class FakePropertyPhotosSource implements PropertyPhotosSource {
  String nextUrl = 'https://cdn.example.com/p1/new.jpg';
  Object? uploadError;
  Object? setError;

  final List<(String, String, int)> uploads = [];
  final List<(String, List<String>)> setCalls = [];

  @override
  Future<String> upload(
    String propertyId, {
    required String filename,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads.add((propertyId, filename, bytes.length));
    if (uploadError != null) throw uploadError!;
    return nextUrl;
  }

  @override
  Future<void> setPhotos(String propertyId, List<String> urls) async {
    setCalls.add((propertyId, List.of(urls)));
    if (setError != null) throw setError!;
  }
}

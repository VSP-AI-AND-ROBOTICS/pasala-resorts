import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/property_photos_repository.dart';
import 'package:pasala/features/browse/providers.dart';
import 'package:pasala/features/owner/property_photos_screen.dart';

import '../../support/fake_property_photos_source.dart';

const _a = 'https://cdn.example.com/p1/a.jpg';
const _b = 'https://cdn.example.com/p1/b.jpg';

Property _property(List<String> images) => Property(
      id: 'p1',
      name: 'Green Acres',
      slug: 'green-acres',
      description: null,
      address: null,
      images: images,
      amenities: const [],
      checkInTime: '14:00',
      checkOutTime: '11:00',
      isActive: true,
    );

class _Harness {
  _Harness(this.images);
  List<String> images;
  int fetches = 0;
  final source = FakePropertyPhotosSource();
  PickedPhoto? picked;
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      propertyProvider.overrideWith((ref, id) async {
        h.fetches++;
        return _property(h.images);
      }),
      propertyPhotosSourceProvider.overrideWithValue(h.source),
    ],
    child: MaterialApp(
      home: PropertyPhotosScreen(
        propertyId: 'p1',
        pickPhoto: () async => h.picked,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows each photo with a remove button', (tester) async {
    await _pump(tester, _Harness([_a, _b]));

    expect(find.byKey(const Key('photo-remove-0')), findsOneWidget);
    expect(find.byKey(const Key('photo-remove-1')), findsOneWidget);
    expect(find.byTooltip('Remove photo'), findsNWidgets(2));
    expect(find.byKey(const Key('photos-empty')), findsNothing);
  });

  testWidgets('with no photos it says so', (tester) async {
    await _pump(tester, _Harness([]));

    expect(find.text('No photos yet'), findsOneWidget);
  });

  testWidgets('Add photo uploads, appends the URL and refetches',
      (tester) async {
    final h = _Harness([_a])
      ..picked = (
        filename: 'pool.jpg',
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/jpeg',
      );
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(h.source.uploads, [('p1', 'pool.jpg', 3)]);
    expect(h.source.setCalls.single.$1, 'p1');
    expect(h.source.setCalls.single.$2, [_a, h.source.nextUrl]);
    expect(h.fetches, 2);
  });

  testWidgets('a cancelled pick sends nothing', (tester) async {
    final h = _Harness([_a]);
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(h.source.uploads, isEmpty);
    expect(h.source.setCalls, isEmpty);
  });

  testWidgets('a failed upload is shown and changes nothing', (tester) async {
    final h = _Harness([_a])
      ..picked = (
        filename: 'pool.jpg',
        bytes: Uint8List.fromList([1]),
        contentType: 'image/jpeg',
      );
    h.source.uploadError = const NetworkFailure();
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('add-photo')));
    await tester.pumpAndSettle();

    expect(find.text('Cannot reach the server. Check your connection.'),
        findsOneWidget);
    expect(h.source.setCalls, isEmpty);
  });

  testWidgets('removing a photo saves the list without it', (tester) async {
    final h = _Harness([_a, _b]);
    await _pump(tester, h);

    await tester.tap(find.byKey(const Key('photo-remove-0')));
    await tester.pumpAndSettle();

    expect(h.source.setCalls.single.$2, [_b]);
  });

  testWidgets('at ten photos Add photo is switched off and says why',
      (tester) async {
    await _pump(
        tester,
        _Harness([
          for (var i = 0; i < maxPropertyPhotos; i++)
            'https://cdn.example.com/p1/$i.jpg',
        ]));

    await tester.scrollUntilVisible(
        find.byKey(const Key('add-photo')), 300,
        scrollable: find.byType(Scrollable).first);
    final button =
        tester.widget<ButtonStyleButton>(find.byKey(const Key('add-photo')));
    expect(button.onPressed, isNull);
    expect(find.text('You can add up to 10 photos.'), findsOneWidget);
  });
}

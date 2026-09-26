import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/core/errors.dart';
import 'package:pasala/data/models/property.dart';
import 'package:pasala/data/repositories/catalog_repository.dart';
import 'package:pasala/features/owner/tax_settings_screen.dart';

/// Records every `updateSettings` call; everything else is unused here.
class _FakeCatalog implements CatalogRepository {
  final saved = <(String, Map<String, dynamic>)>[];
  Object? failWith;

  @override
  Future<void> updateSettings(String propertyId, Map<String, dynamic> fields) async {
    final failure = failWith;
    if (failure != null) throw failure;
    saved.add((propertyId, fields));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

const _property = Property(
  id: 'p1',
  name: 'Pasala Farm House',
  slug: 'pasala-farm-house',
  description: null,
  address: null,
  images: [],
  amenities: [],
  checkInTime: '14:00',
  checkOutTime: '11:00',
  isActive: true,
  taxPct: 12,
  fnbTaxPct: 5,
  spaTaxPct: 18,
  gstin: '29ABCDE1234F1Z5',
);

/// Pushes the screen over a home page, as Owner Settings does, so Save can
/// pop it. Tall enough that every field is built.
Future<void> _open(WidgetTester tester, _FakeCatalog catalog) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [catalogRepositoryProvider.overrideWithValue(catalog)],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const TaxSettingsScreen(property: _property),
            )),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _enter(WidgetTester tester, String key, String text) =>
    tester.enterText(find.byKey(Key(key)), text);

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the room, food and spa rates of the resort', (tester) async {
    await _open(tester, _FakeCatalog());

    expect(_text(tester, 'tax-pct-field'), '12');
    expect(_text(tester, 'tax-fnb-field'), '5');
    expect(_text(tester, 'tax-spa-field'), '18');
    expect(_text(tester, 'tax-gstin-field'), '29ABCDE1234F1Z5');
    expect(find.text('Room tax rate (%)'), findsOneWidget);
    expect(find.text('Food & drink tax (%)'), findsOneWidget);
    expect(find.text('Spa & activities tax (%)'), findsOneWidget);
    expect(find.text('Already included in menu prices'), findsOneWidget);
    expect(find.text('Already included in activity prices'), findsOneWidget);
    expect(
        find.text('Each order and sale keeps the rate it was made at. '
            'Changing a rate affects new sales only.'),
        findsOneWidget);
  });

  testWidgets('Save sends all four settings in one update and closes', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '12');
    await _enter(tester, 'tax-spa-field', '18.5');
    await _save(tester);

    expect(catalog.saved, hasLength(1));
    expect(catalog.saved.single.$1, 'p1');
    expect(catalog.saved.single.$2, {
      'tax_pct': 12,
      'fnb_tax_pct': 12,
      'spa_tax_pct': 18.5,
      'gstin': '29ABCDE1234F1Z5',
    });
    expect(find.byType(TaxSettingsScreen), findsNothing);
  });

  testWidgets('28% and a blank GSTIN are saved as 28 and null', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '28');
    await _enter(tester, 'tax-gstin-field', '  ');
    await _save(tester);

    expect(catalog.saved.single.$2['fnb_tax_pct'], 28);
    expect(catalog.saved.single.$2['gstin'], isNull);
  });

  testWidgets('a food rate above 28 is refused before saving', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-fnb-field', '28.5');
    await _save(tester);

    expect(find.text('Enter a food & drink tax rate between 0 and 28.'), findsOneWidget);
    expect(catalog.saved, isEmpty);
    expect(find.byType(TaxSettingsScreen), findsOneWidget);
  });

  testWidgets('a rate that is not a number is refused', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    for (final typed in ['18%', 'NaN', '5,5', '']) {
      await _enter(tester, 'tax-spa-field', typed);
      await _save(tester);
      expect(find.text('Enter a spa & activities tax rate between 0 and 28.'), findsOneWidget,
          reason: typed);
    }
    expect(catalog.saved, isEmpty);
  });

  testWidgets('the room rate keeps its 0 to 100 range', (tester) async {
    final catalog = _FakeCatalog();
    await _open(tester, catalog);

    await _enter(tester, 'tax-pct-field', '101');
    await _save(tester);

    expect(find.text('Enter a room tax rate between 0 and 100.'), findsOneWidget);
    expect(catalog.saved, isEmpty);
  });

  testWidgets('a server refusal shows its message and keeps the screen open', (tester) async {
    final catalog = _FakeCatalog()..failWith = const TaxRateOutOfRange();
    await _open(tester, catalog);

    await _save(tester);

    expect(find.text('Food and spa tax rates must be between 0% and 28%.'), findsOneWidget);
    expect(find.byType(TaxSettingsScreen), findsOneWidget);
  });
}

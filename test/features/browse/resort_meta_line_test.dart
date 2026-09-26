import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/features/browse/resort_meta_line.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('shows rating, distance and price', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine(
      avgRating: 4.5,
      reviewCount: 2,
      distanceKm: 12.3,
      minPrice: 4000,
    )));

    expect(find.text('4.5 (2)'), findsOneWidget);
    expect(find.text('12 km'), findsOneWidget);
    expect(find.text('from ₹4,000 / night'), findsOneWidget);
    expect(find.bySemanticsLabel('Rated 4.5 out of 5 from 2 reviews'),
        findsOneWidget);
    expect(find.bySemanticsLabel('12 km away'), findsOneWidget);
  });

  testWidgets('a single review reads "1 review"', (tester) async {
    await tester.pumpWidget(
        _wrap(const ResortMetaLine(avgRating: 5, reviewCount: 1)));

    expect(find.text('5.0 (1)'), findsOneWidget);
    expect(find.bySemanticsLabel('Rated 5.0 out of 5 from 1 review'),
        findsOneWidget);
  });

  testWidgets('a nearby resort reads "< 1 km"', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine(distanceKm: 0.6)));

    expect(find.text('< 1 km'), findsOneWidget);
  });

  testWidgets('shows no rating without reviews', (tester) async {
    await tester.pumpWidget(
        _wrap(const ResortMetaLine(avgRating: 4.0, reviewCount: 0, minPrice: 2500)));

    expect(find.byIcon(Icons.star_rounded), findsNothing);
    expect(find.text('from ₹2,500 / night'), findsOneWidget);
  });

  testWidgets('renders nothing when there is nothing to show', (tester) async {
    await tester.pumpWidget(_wrap(const ResortMetaLine()));

    expect(find.byType(Wrap), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

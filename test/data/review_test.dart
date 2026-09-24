import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/review.dart';

Map<String, dynamic> _json({String? authorName, bool withAuthor = false}) => {
      'id': 'r1',
      'reservation_id': 'res-1',
      'customer_id': 'cust-1',
      'farmhouse_rating': 5,
      'cleanliness_rating': 5,
      'food_rating': 4,
      'service_rating': 5,
      'activities_rating': 4,
      'overall_rating': 5,
      'feedback': 'Lovely stay',
      'created_at': '2026-09-01T10:00:00Z',
      if (withAuthor) 'author_name': authorName,
    };

void main() {
  test('parses the first name from the row\'s author_name', () {
    final r = Review.fromJson(
        _json(authorName: 'Ramesh Kumar', withAuthor: true));
    expect(r.customerFirstName, 'Ramesh');
  });

  test('is null when author_name is absent entirely', () {
    final r = Review.fromJson(_json());
    expect(r.customerFirstName, isNull);
  });

  test('is null when author_name itself is null', () {
    final r = Review.fromJson(_json(withAuthor: true));
    expect(r.customerFirstName, isNull);
  });

  test('is null when author_name is blank', () {
    final r = Review.fromJson(_json(authorName: '   ', withAuthor: true));
    expect(r.customerFirstName, isNull);
  });

  test('ignores a profiles embed -- the name comes only from author_name',
      () {
    final r = Review.fromJson({
      ..._json(),
      'profiles': {'full_name': 'Ramesh Kumar'},
    });
    expect(r.customerFirstName, isNull);
  });

  test('parses every rating and the feedback text', () {
    final r = Review.fromJson(_json());
    expect(r.overallRating, 5);
    expect(r.foodRating, 4);
    expect(r.feedback, 'Lovely stay');
    expect(r.createdAt, DateTime.parse('2026-09-01T10:00:00Z'));
  });
}

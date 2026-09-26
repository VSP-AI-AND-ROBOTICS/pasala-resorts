import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/listing.dart';
import 'package:pasala/data/models/subscription.dart';

Map<String, dynamic> _flags({
  bool photos = false,
  bool unit = false,
  bool rates = false,
  bool payments = false,
  bool cancellation = false,
  bool tax = false,
}) => {
  'has_photos': photos,
  'has_unit': unit,
  'has_rates': rates,
  'has_payment_settings': payments,
  'has_cancellation_policy': cancellation,
  'has_tax_details': tax,
};

void main() {
  group('ListingSetup.fromJson', () {
    test('reads the status, the submission and each flag', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'pending',
        'submitted_at': null,
        ..._flags(unit: true, rates: true),
      });

      expect(setup.isPending, isTrue);
      expect(setup.submittedAt, isNull);
      expect(setup.isDone(SetupStep.units), isTrue);
      expect(setup.isDone(SetupStep.photos), isFalse);
      expect(setup.doneCount, 2);
      expect(setup.complete, isFalse);
    });

    test('is complete only when all six are done', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'pending',
        'submitted_at': '2026-09-20T10:00:00+00:00',
        ..._flags(
          photos: true,
          unit: true,
          rates: true,
          payments: true,
          cancellation: true,
          tax: true,
        ),
      });

      expect(setup.complete, isTrue);
      expect(setup.doneCount, 6);
      expect(setup.submittedAt, DateTime.utc(2026, 9, 20, 10));
    });

    test('a missing flag counts as not done', () {
      final setup = ListingSetup.fromJson({
        'property_status': 'active',
        'submitted_at': null,
      });

      expect(setup.doneCount, 0);
      expect(setup.isPending, isFalse);
    });
  });

  group('ListingApplication', () {
    Map<String, dynamic> row({
      String? submittedAt,
      String? decision,
      String? reason,
      String status = 'pending',
    }) => {
      'property_id': 'r1',
      'name': 'Green Acres',
      'city': 'Nashik',
      'tier': 'pro',
      'property_status': status,
      'created_at': '2026-09-19T10:00:00+00:00',
      'submitted_at': submittedAt,
      'decision': decision,
      'decided_at': decision == null ? null : '2026-09-24T10:00:00+00:00',
      'rejection_reason': reason,
    };

    test('parses a row still being set up', () {
      final app = ListingApplication.fromJson(row());

      expect(app.propertyId, 'r1');
      expect(app.tier, SubscriptionTier.pro);
      expect(app.isOpen, isTrue);
      expect(app.statusLine, 'Setting up');
    });

    test('a submitted row says since when', () {
      final app = ListingApplication.fromJson(
        row(submittedAt: '2026-09-20T12:00:00+00:00'),
      );

      expect(app.statusLine, 'Waiting for review since 20 Sep 2026');
    });

    test('an approved row is closed', () {
      final app = ListingApplication.fromJson(
        row(decision: 'approved', status: 'active'),
      );

      expect(app.isOpen, isFalse);
      expect(app.decision, ListingDecision.approved);
      expect(app.statusLine, 'Approved');
    });

    test('a rejected row carries the reason', () {
      final app = ListingApplication.fromJson(
        row(
          decision: 'rejected',
          reason: 'Photos do not match the address.',
          status: 'archived',
        ),
      );

      expect(app.statusLine, 'Not approved: Photos do not match the address.');
      expect(app.propertyStatus, 'archived');
    });

    test('an unknown decision is rejected, not defaulted', () {
      expect(() => listingDecisionFromDb('maybe'), throwsArgumentError);
    });
  });

  group('PendingListing.fromJson', () {
    Map<String, dynamic> row({String? submittedAt, bool tax = true}) => {
      'property_id': 'r1',
      'name': 'Green Acres',
      'city': 'Nashik',
      'address': '12 Vineyard Road, Nashik',
      'contact_phone': '+919876543210',
      'description': 'Vineyard cottages with a pool and a view.',
      'applicant_email': 'asha@example.com',
      'applicant_name': null,
      'tier': 'starter',
      'created_at': '2026-09-19T10:00:00+00:00',
      'submitted_at': submittedAt,
      ..._flags(
        photos: true,
        unit: true,
        rates: true,
        payments: true,
        cancellation: true,
        tax: tax,
      ),
    };

    test('can be approved only when submitted and complete', () {
      final ready = PendingListing.fromJson(
        row(submittedAt: '2026-09-20T12:00:00+00:00'),
      );
      final notSubmitted = PendingListing.fromJson(row());
      final incomplete = PendingListing.fromJson(
        row(submittedAt: '2026-09-20T10:00:00+00:00', tax: false),
      );

      expect(ready.canApprove, isTrue);
      expect(ready.applicantName, isNull);
      expect(notSubmitted.submitted, isFalse);
      expect(notSubmitted.canApprove, isFalse);
      expect(incomplete.setupComplete, isFalse);
      expect(incomplete.canApprove, isFalse);
    });
  });

  group('validators mirror apply_for_listing', () {
    test('name: 2 to 80 characters after trimming', () {
      expect(
        validateListingName('  '),
        'Enter the resort name (2 to 80 characters).',
      );
      expect(validateListingName('A'), isNotNull);
      expect(validateListingName('A' * 81), isNotNull);
      expect(validateListingName(' Green Acres '), isNull);
    });

    test('city: 2 to 60 characters', () {
      expect(validateListingCity(''), 'Enter the city (2 to 60 characters).');
      expect(validateListingCity('Nashik'), isNull);
    });

    test('address: 5 to 300 characters', () {
      expect(
        validateListingAddress('Road'),
        'Enter the full address (5 to 300 characters).',
      );
      expect(validateListingAddress('12 Vineyard Road'), isNull);
    });

    test('phone: 10 to 13 digits, spaces and dashes ignored, optional +', () {
      const message = 'Enter a contact phone number, e.g. +91 98765 43210.';
      expect(validateListingPhone('+91 98765 43210'), isNull);
      expect(validateListingPhone('98765-43210'), isNull);
      expect(validateListingPhone('12345'), message);
      expect(validateListingPhone('phone me'), message);
      expect(validateListingPhone('+91 98765 43210 99'), message);
    });

    test('description: 20 to 500 characters', () {
      expect(
        validateListingDescription('Nice place'),
        'Describe the resort in 20 to 500 characters.',
      );
      expect(validateListingDescription('A' * 20), isNull);
      expect(validateListingDescription('A' * 501), isNotNull);
    });

    test('rejection reason: 5 to 500 characters', () {
      expect(
        validateRejectionReason(' no '),
        'Give the owner a reason (5 to 500 characters).',
      );
      expect(validateRejectionReason('Photos do not match.'), isNull);
    });
  });

  test('every step has a title and a hint', () {
    expect(SetupStep.values.map((s) => s.title).toList(), [
      'Add photos',
      'Add at least one unit',
      'Set rates for every unit',
      'Payment settings',
      'Cancellation policy',
      'GSTIN and tax',
    ]);
    expect(SetupStep.tax.hint, 'Your 15-character GSTIN');
  });
}

import '../../core/format.dart';
import 'subscription.dart';

/// One item on a pending resort's setup checklist (spec decision 10). The
/// server decides whether each is done (`listing_setup_status`,
/// 0059_resort_self_listing.sql); the app only names them.
enum SetupStep { photos, units, rates, payments, cancellation, tax }

extension SetupStepCopy on SetupStep {
  String get title => switch (this) {
    SetupStep.photos => 'Add photos',
    SetupStep.units => 'Add at least one unit',
    SetupStep.rates => 'Set rates for every unit',
    SetupStep.payments => 'Payment settings',
    SetupStep.cancellation => 'Cancellation policy',
    SetupStep.tax => 'GSTIN and tax',
  };

  String get hint => switch (this) {
    SetupStep.photos => 'Guests see these on your listing',
    SetupStep.units => 'The rooms, cottages or villas guests book',
    SetupStep.rates => 'A base or weekend price for each active unit',
    SetupStep.payments => 'Advance % and the payment methods you accept',
    SetupStep.cancellation => 'How much guests get back when they cancel',
    SetupStep.tax => 'Your 15-character GSTIN',
  };
}

/// The six `has_*` columns `listing_setup_status` and
/// `platform_listing_applications` share. A missing column counts as not
/// done.
Map<SetupStep, bool> setupFlagsFromRow(Map<String, dynamic> row) => {
  SetupStep.photos: row['has_photos'] as bool? ?? false,
  SetupStep.units: row['has_unit'] as bool? ?? false,
  SetupStep.rates: row['has_rates'] as bool? ?? false,
  SetupStep.payments: row['has_payment_settings'] as bool? ?? false,
  SetupStep.cancellation: row['has_cancellation_policy'] as bool? ?? false,
  SetupStep.tax: row['has_tax_details'] as bool? ?? false,
};

DateTime? _timeOrNull(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toUtc();

/// `listing_setup_status(p_property)`: the resort's status, when it was
/// submitted, and which checklist items are done.
class ListingSetup {
  const ListingSetup({
    required this.propertyStatus,
    required this.done,
    this.submittedAt,
  });

  factory ListingSetup.fromJson(Map<String, dynamic> json) => ListingSetup(
    propertyStatus: json['property_status'] as String,
    submittedAt: _timeOrNull(json['submitted_at']),
    done: setupFlagsFromRow(json),
  );

  /// `properties.status`: `pending` while it waits, `active` once approved.
  final String propertyStatus;
  final DateTime? submittedAt;
  final Map<SetupStep, bool> done;

  bool isDone(SetupStep step) => done[step] ?? false;
  int get doneCount => SetupStep.values.where(isDone).length;
  bool get complete => doneCount == SetupStep.values.length;
  bool get isPending => propertyStatus == 'pending';
}

enum ListingDecision { approved, rejected }

/// Unknown text is rejected rather than defaulted, like the other enums.
ListingDecision? listingDecisionFromDb(String? raw) => switch (raw) {
  null => null,
  'approved' => ListingDecision.approved,
  'rejected' => ListingDecision.rejected,
  _ => throw ArgumentError('Unknown listing decision: $raw'),
};

/// One row of `my_listing_applications()`: an application the signed-in
/// user made, including decided ones (a rejected resort is archived and no
/// longer reachable through the membership, so this is where its reason
/// shows).
class ListingApplication {
  const ListingApplication({
    required this.propertyId,
    required this.name,
    required this.city,
    required this.tier,
    required this.propertyStatus,
    required this.createdAt,
    this.submittedAt,
    this.decision,
    this.decidedAt,
    this.rejectionReason,
  });

  factory ListingApplication.fromJson(Map<String, dynamic> json) =>
      ListingApplication(
        propertyId: json['property_id'] as String,
        name: json['name'] as String,
        city: json['city'] as String? ?? '',
        tier: subscriptionTierFromDb(json['tier'] as String),
        propertyStatus: json['property_status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        submittedAt: _timeOrNull(json['submitted_at']),
        decision: listingDecisionFromDb(json['decision'] as String?),
        decidedAt: _timeOrNull(json['decided_at']),
        rejectionReason: json['rejection_reason'] as String?,
      );

  final String propertyId;
  final String name;
  final String city;
  final SubscriptionTier tier;
  final String propertyStatus;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final ListingDecision? decision;
  final DateTime? decidedAt;
  final String? rejectionReason;

  /// Still waiting for a decision (being set up, or submitted).
  bool get isOpen => decision == null;

  String get statusLine => switch (decision) {
    ListingDecision.approved => 'Approved',
    ListingDecision.rejected =>
      'Not approved: ${rejectionReason ?? 'no reason given'}',
    null =>
      submittedAt == null
          ? 'Setting up'
          : 'Waiting for review since ${formatDate(submittedAt!.toLocal())}',
  };
}

/// One row of `platform_listing_applications()`: an undecided application
/// as the platform admin reviews it.
class PendingListing {
  const PendingListing({
    required this.propertyId,
    required this.name,
    required this.city,
    required this.address,
    required this.contactPhone,
    required this.description,
    required this.applicantEmail,
    required this.tier,
    required this.createdAt,
    required this.setup,
    this.applicantName,
    this.submittedAt,
  });

  factory PendingListing.fromJson(Map<String, dynamic> json) => PendingListing(
    propertyId: json['property_id'] as String,
    name: json['name'] as String,
    city: json['city'] as String? ?? '',
    address: json['address'] as String? ?? '',
    contactPhone: json['contact_phone'] as String? ?? '',
    description: json['description'] as String? ?? '',
    applicantEmail: json['applicant_email'] as String? ?? '',
    applicantName: json['applicant_name'] as String?,
    tier: subscriptionTierFromDb(json['tier'] as String),
    createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
    submittedAt: _timeOrNull(json['submitted_at']),
    setup: setupFlagsFromRow(json),
  );

  final String propertyId;
  final String name;
  final String city;
  final String address;
  final String contactPhone;
  final String description;
  final String applicantEmail;
  final String? applicantName;
  final SubscriptionTier tier;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final Map<SetupStep, bool> setup;

  bool get submitted => submittedAt != null;
  bool get setupComplete => SetupStep.values.every((s) => setup[s] ?? false);

  /// `approve_listing` refuses anything else (P0040).
  bool get canApprove => submitted && setupComplete;
}

/// What the "List your resort" form sends to `apply_for_listing`.
class ListingInput {
  const ListingInput({
    required this.name,
    required this.city,
    required this.address,
    required this.contactPhone,
    required this.description,
    required this.tier,
  });

  final String name;
  final String city;
  final String address;
  final String contactPhone;
  final String description;
  final SubscriptionTier tier;
}

// Validators: the same rules and messages as apply_for_listing and
// reject_listing (P0005), so the form catches them before the server does.

String? _length(String? value, int min, int max, String message) {
  final length = (value ?? '').trim().length;
  return length < min || length > max ? message : null;
}

String? validateListingName(String? value) =>
    _length(value, 2, 80, 'Enter the resort name (2 to 80 characters).');

String? validateListingCity(String? value) =>
    _length(value, 2, 60, 'Enter the city (2 to 60 characters).');

String? validateListingAddress(String? value) =>
    _length(value, 5, 300, 'Enter the full address (5 to 300 characters).');

String? validateListingPhone(String? value) {
  final compact = (value ?? '').trim().replaceAll(RegExp(r'[ -]'), '');
  return RegExp(r'^\+?[0-9]{10,13}$').hasMatch(compact)
      ? null
      : 'Enter a contact phone number, e.g. +91 98765 43210.';
}

String? validateListingDescription(String? value) =>
    _length(value, 20, 500, 'Describe the resort in 20 to 500 characters.');

String? validateRejectionReason(String? value) =>
    _length(value, 5, 500, 'Give the owner a reason (5 to 500 characters).');

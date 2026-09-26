import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/coupon.dart';
import '../../data/repositories/coupon_repository.dart';

/// Picks a day for "Valid from" / "Valid until". Tests pass their own.
typedef CouponDatePicker =
    Future<DateTime?> Function(BuildContext context, DateTime initial);

Future<DateTime?> _showDatePicker(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

/// Opens [CouponForm] full screen: a new coupon when [coupon] is null,
/// otherwise an edit of it. Completes with true once the coupon was saved,
/// false when the form was closed without saving.
Future<bool> showCouponForm(
  BuildContext context, {
  required String propertyId,
  Coupon? coupon,
  CouponDatePicker? pickDate,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => Dialog.fullscreen(
      child: CouponForm(
        propertyId: propertyId,
        coupon: coupon,
        pickDate: pickDate ?? _showDatePicker,
      ),
    ),
  );
  return saved ?? false;
}

enum _Audience { everyone, oneGuest }

/// Upper-cases the code as it is typed, so what the admin sees is what is
/// saved (`coupons_code_upper`) and what a guest must type.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// The create/edit form for one coupon. It checks locally everything
/// `coupon_check_input` checks except what only the server knows (a code
/// already taken, a guest's bookings), so most mistakes never leave the
/// device. A server refusal stays on the form with its message. It pops
/// itself with its own context: it lives on the dialog's route, never the
/// screen's.
class CouponForm extends ConsumerStatefulWidget {
  const CouponForm({
    super.key,
    required this.propertyId,
    this.coupon,
    this.pickDate = _showDatePicker,
  });

  final String propertyId;
  final Coupon? coupon;
  final CouponDatePicker pickDate;

  @override
  ConsumerState<CouponForm> createState() => _CouponFormState();
}

class _CouponFormState extends ConsumerState<CouponForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _value;
  late final TextEditingController _minAmount;
  late final TextEditingController _usageLimit;
  late final TextEditingController _guestEmail;
  late CouponKind _kind;
  DateTime? _validFrom;
  DateTime? _validUntil;
  late _Audience _audience;
  ResortGuest? _guest;
  String? _guestError;
  String? _datesError;
  String? _formError;
  bool _finding = false;
  bool _saving = false;

  bool get _isEdit => widget.coupon != null;
  int get _used => widget.coupon?.usedCount ?? 0;

  static String _numText(num n) =>
      n % 1 == 0 ? n.toInt().toString() : n.toString();

  @override
  void initState() {
    super.initState();
    final c = widget.coupon;
    _code = TextEditingController(text: c?.code ?? '');
    _value = TextEditingController(text: c == null ? '' : _numText(c.value));
    _minAmount = TextEditingController(
      text: c?.minAmount == null ? '' : _numText(c!.minAmount!),
    );
    _usageLimit = TextEditingController(text: c?.usageLimit?.toString() ?? '');
    _guestEmail = TextEditingController(text: c?.guest?.email ?? '');
    _kind = c?.kind ?? CouponKind.percent;
    _validFrom = c?.validFrom;
    _validUntil = c?.validUntil;
    _guest = c?.guest;
    _audience = _guest == null ? _Audience.everyone : _Audience.oneGuest;
  }

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minAmount.dispose();
    _usageLimit.dispose();
    _guestEmail.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool from}) async {
    final initial =
        (from ? _validFrom : _validUntil) ?? _validFrom ?? DateTime.now();
    final picked = await widget.pickDate(context, initial);
    if (picked == null || !mounted) return;
    final day = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      if (from) {
        _validFrom = day;
      } else {
        _validUntil = day;
      }
      _datesError = null;
    });
  }

  Future<void> _findGuest() async {
    final email = _guestEmail.text.trim();
    if (email.isEmpty) {
      setState(() => _guestError = "Enter the guest's email.");
      return;
    }
    setState(() {
      _finding = true;
      _guest = null;
      _guestError = null;
    });
    try {
      final guest = await ref
          .read(couponSourceProvider)
          .findGuest(widget.propertyId, email);
      if (!mounted) return;
      setState(() {
        _guest = guest;
        _guestError = guest == null
            ? 'No guest with that email has booked at this resort.'
            : null;
      });
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() => _guestError = e.message);
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _save() async {
    final fieldsOk = _formKey.currentState!.validate();
    final datesOk = _validFrom == null ||
        _validUntil == null ||
        !_validUntil!.isBefore(_validFrom!);
    final guestOk = _audience == _Audience.everyone || _guest != null;
    setState(() {
      _datesError =
          datesOk ? null : 'The end date must be on or after the start date.';
      if (!guestOk) _guestError = 'Find the guest first, or choose Everyone.';
      _formError = null;
    });
    if (!fieldsOk || !datesOk || !guestOk) return;

    final minText = _minAmount.text.trim();
    final limitText = _usageLimit.text.trim();
    final draft = CouponDraft(
      code: normalizeCouponCode(_code.text),
      kind: _kind,
      value: num.parse(_value.text.trim()),
      minAmount: minText.isEmpty ? null : num.parse(minText),
      validFrom: _validFrom,
      validUntil: _validUntil,
      usageLimit: limitText.isEmpty ? null : int.parse(limitText),
      guestId: _audience == _Audience.oneGuest ? _guest!.userId : null,
    );

    setState(() => _saving = true);
    final source = ref.read(couponSourceProvider);
    try {
      if (_isEdit) {
        await source.update(widget.coupon!.id, draft);
      } else {
        await source.create(widget.propertyId, draft);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on BookingFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.error);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('coupon-cancel'),
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        title: Text(_isEdit ? 'Edit ${widget.coupon!.code}' : 'New coupon'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            TextFormField(
              key: const Key('coupon-code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              decoration: const InputDecoration(
                labelText: 'Code',
                helperText:
                    '3–24 letters, numbers, - or _. Guests type this when '
                    'they book.',
              ),
              validator: (v) =>
                  couponCodePattern.hasMatch(normalizeCouponCode(v ?? ''))
                      ? null
                      : 'Use 3–24 letters, numbers, - or _.',
            ),
            const SizedBox(height: Spacing.md),
            SegmentedButton<CouponKind>(
              key: const Key('coupon-kind'),
              segments: const [
                ButtonSegment(
                  value: CouponKind.percent,
                  label: Text('Percentage'),
                  icon: Icon(Icons.percent),
                ),
                ButtonSegment(
                  value: CouponKind.fixed,
                  label: Text('Fixed amount'),
                  icon: Icon(Icons.currency_rupee),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('coupon-value'),
              controller: _value,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _kind == CouponKind.percent
                    ? 'Discount (%)'
                    : 'Discount (₹)',
              ),
              validator: (v) {
                final n = num.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter a discount above 0.';
                if (_kind == CouponKind.percent && n > 100) {
                  return 'A percentage can be at most 100.';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),
            TextFormField(
              key: const Key('coupon-min-amount'),
              controller: _minAmount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Minimum booking amount (₹, optional)',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = num.tryParse(t);
                return n == null || n < 0
                    ? 'Enter 0 or more, or leave it empty.'
                    : null;
              },
            ),
            const SizedBox(height: Spacing.sm),
            _DateRow(
              key: const Key('coupon-valid-from'),
              clearKey: const Key('coupon-valid-from-clear'),
              label: 'Valid from',
              value: _validFrom,
              emptyText: 'Any time',
              onPick: () => _pick(from: true),
              onClear: () => setState(() => _validFrom = null),
            ),
            _DateRow(
              key: const Key('coupon-valid-until'),
              clearKey: const Key('coupon-valid-until-clear'),
              label: 'Valid until',
              value: _validUntil,
              emptyText: 'No end date',
              onPick: () => _pick(from: false),
              onClear: () => setState(() => _validUntil = null),
            ),
            if (_datesError != null)
              Text(
                _datesError!,
                key: const Key('coupon-dates-error'),
                style: errorStyle,
              ),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              key: const Key('coupon-usage-limit'),
              controller: _usageLimit,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Usage limit (optional)',
                helperText: _isEdit
                    ? 'Used $_used so far'
                    : 'Leave empty for no limit',
              ),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final n = int.tryParse(t);
                if (n == null || n < 1) {
                  return 'Enter 1 or more, or leave it empty.';
                }
                if (n < _used) {
                  return 'Already used $_used times — the limit cannot be '
                      'lower.';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),
            Text('Who can use it',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            SegmentedButton<_Audience>(
              key: const Key('coupon-audience'),
              segments: const [
                ButtonSegment(
                  value: _Audience.everyone,
                  label: Text('Everyone'),
                  icon: Icon(Icons.public),
                ),
                ButtonSegment(
                  value: _Audience.oneGuest,
                  label: Text('One guest'),
                  icon: Icon(Icons.person_outline),
                ),
              ],
              selected: {_audience},
              onSelectionChanged: (s) => setState(() {
                _audience = s.first;
                _guestError = null;
              }),
            ),
            if (_audience == _Audience.oneGuest) ...[
              const SizedBox(height: Spacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('coupon-guest-email'),
                      controller: _guestEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: "Guest's email",
                        helperText: 'Someone who has booked at this resort',
                      ),
                      // A found guest belongs to the email that found
                      // them: editing the email forgets the match.
                      onChanged: (text) {
                        if (_guest != null && text.trim() != _guest!.email) {
                          setState(() => _guest = null);
                        }
                      },
                      onSubmitted: (_) => _findGuest(),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  OutlinedButton(
                    key: const Key('coupon-guest-find'),
                    onPressed: _finding ? null : _findGuest,
                    child: Text(_finding ? 'Finding…' : 'Find'),
                  ),
                ],
              ),
              if (_guest != null)
                ListTile(
                  key: const Key('coupon-guest-found'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person),
                  title: Text(_guest!.name),
                  subtitle: Text(_guest!.email),
                ),
              if (_guestError != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Text(
                    _guestError!,
                    key: const Key('coupon-guest-error'),
                    style: errorStyle,
                  ),
                ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: Spacing.md),
              Text(
                _formError!,
                key: const Key('coupon-form-error'),
                style: errorStyle,
              ),
            ],
            const SizedBox(height: Spacing.lg),
            FilledButton(
              key: const Key('coupon-save'),
              onPressed: _saving ? null : _save,
              child: Text(
                _saving
                    ? 'Saving…'
                    : _isEdit
                        ? 'Save changes'
                        : 'Create coupon',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One optional date: tap to pick, the clear button to go back to
/// [emptyText].
class _DateRow extends StatelessWidget {
  const _DateRow({
    super.key,
    required this.clearKey,
    required this.label,
    required this.value,
    required this.emptyText,
    required this.onPick,
    required this.onClear,
  });

  final Key clearKey;
  final String label;
  final DateTime? value;
  final String emptyText;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.event_outlined),
    title: Text(label),
    subtitle: Text(value == null ? emptyText : formatDate(value!)),
    onTap: onPick,
    trailing: value == null
        ? null
        : IconButton(
            key: clearKey,
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: onClear,
          ),
  );
}

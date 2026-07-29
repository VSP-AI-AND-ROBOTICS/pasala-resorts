import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/rate_rule.dart';
import '../../data/repositories/rate_repository.dart';

/// Monday-first weekday labels: index 0 is ISO weekday 1 (Monday), index 6
/// is ISO weekday 7 (Sunday) -- matching `extract(isodow from date)` in
/// `resolve_rate_rule` and the seeded weekend rule's `{6,7}` (Sat, Sun).
const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

final _dateFormat = DateFormat('d MMM yyyy');

String _kindLabel(RateKind kind) => switch (kind) {
      RateKind.base => 'Base',
      RateKind.weekend => 'Weekend',
      RateKind.override_ => 'Override',
    };

/// Validates the two DB check constraints on `rate_rules` client-side, so a
/// bad save never reaches Postgres:
/// - `rate_rules_override_dates`: an `override` row must have both dates.
/// - `rate_rules_date_order`: `valid_to >= valid_from` when both are set.
///
/// Pure and top-level so it's directly unit-testable without driving the
/// real `showDateRangePicker` UI, which by construction never lets a user
/// pick an end date before the start date.
String? validateRateRuleDates({
  required RateKind kind,
  required DateTime? validFrom,
  required DateTime? validTo,
}) {
  if (kind == RateKind.override_ && (validFrom == null || validTo == null)) {
    return 'Override rules need both a start and end date.';
  }
  if (validFrom != null && validTo != null && validTo.isBefore(validFrom)) {
    return 'End date must be on or after the start date.';
  }
  return null;
}

/// Admin's rate-rule list for a unit. Reachable at `/admin/rates/:unitId`,
/// including straight after creating a unit (see `UnitFormScreen`), since a
/// unit with no rate rule at all cannot be quoted (`get_quote` raises
/// P0004).
class RateRulesScreen extends ConsumerWidget {
  const RateRulesScreen({super.key, required this.unitId});

  final String unitId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rateRulesProvider(unitId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rates')),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(
          error: e,
          onRetry: () => ref.invalidate(rateRulesProvider(unitId)),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('No rate rules yet.'));
          }
          final grouped = <RateKind, List<RateRule>>{};
          for (final rule in list) {
            grouped.putIfAbsent(rule.kind, () => []).add(rule);
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final kind in RateKind.values)
                if (grouped[kind] != null && grouped[kind]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _kindLabel(kind),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  for (final rule in grouped[kind]!)
                    Card(
                      child: ListTile(
                        title: Text(rule.label ?? _kindLabel(rule.kind)),
                        subtitle: Text([
                          formatInr(rule.price),
                          'priority ${rule.priority}',
                          if (rule.kind == RateKind.override_ &&
                              rule.validFrom != null &&
                              rule.validTo != null)
                            '${_dateFormat.format(rule.validFrom!)} – '
                                '${_dateFormat.format(rule.validTo!)}',
                        ].join(' · ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) =>
                              _onMenuSelected(context, ref, rule, value),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ),
                ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RateRuleFormScreen(unitId: unitId),
        )),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _onMenuSelected(
      BuildContext context, WidgetRef ref, RateRule rule, String value) {
    switch (value) {
      case 'edit':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RateRuleFormScreen(unitId: unitId, existing: rule),
        ));
      case 'delete':
        _delete(context, ref, rule);
    }
  }

  /// Confirms before deleting: deleting the last rule that matches a unit's
  /// dates makes that unit unquotable (`get_quote` raises `P0004`), which
  /// would otherwise reach a customer as an unexplained booking failure with
  /// no warning to the admin who caused it. This dialog does not attempt to
  /// work out whether [rule] is actually the last matching rule -- that
  /// would need the same date-resolution logic as `resolve_rate_rule` --
  /// it just makes sure a delete is never one accidental tap.
  Future<void> _delete(
      BuildContext context, WidgetRef ref, RateRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteRuleDialog(rule: rule),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(rateRepositoryProvider).delete(rule.id);
      ref.invalidate(rateRulesProvider(unitId));
    } on BookingFailure catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Names the rule being deleted so the admin knows exactly what they are
/// about to remove -- mirroring the confirm/dismiss shape of
/// `_CancelBookingDialog` in `booking_detail_screen.dart`.
class _DeleteRuleDialog extends StatelessWidget {
  const _DeleteRuleDialog({required this.rule});

  final RateRule rule;

  @override
  Widget build(BuildContext context) {
    final label = rule.label ?? _kindLabel(rule.kind);
    return AlertDialog(
      title: Text('Delete "$label"?'),
      content: const Text(
        'If this is the only rule that covers some of this unit\'s dates, '
        'those dates will no longer be quotable. This cannot be undone.',
      ),
      actions: [
        TextButton(
          key: const Key('keep-rule-button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('confirm-delete-rule-button'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

/// Create/edit form for a [RateRule]. Pushed imperatively from
/// [RateRulesScreen] rather than routed, matching `UnitFormScreen` and
/// `PropertyFormScreen`.
class RateRuleFormScreen extends ConsumerStatefulWidget {
  const RateRuleFormScreen({super.key, required this.unitId, this.existing});

  final String unitId;
  final RateRule? existing;

  @override
  ConsumerState<RateRuleFormScreen> createState() =>
      _RateRuleFormScreenState();
}

class _RateRuleFormScreenState extends ConsumerState<RateRuleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _label;
  late final TextEditingController _price;
  late final TextEditingController _extraGuestPrice;
  late final TextEditingController _cleaningFee;
  late final TextEditingController _priority;
  late RateKind _kind;
  late Set<int> _weekdays;
  DateTime? _validFrom;
  DateTime? _validTo;
  String? _dateError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _label = TextEditingController(text: existing?.label ?? '');
    _price = TextEditingController(text: existing?.price.toString() ?? '');
    _extraGuestPrice = TextEditingController(
        text: existing?.extraGuestPrice.toString() ?? '0');
    _cleaningFee =
        TextEditingController(text: existing?.cleaningFee.toString() ?? '0');
    _priority =
        TextEditingController(text: existing?.priority.toString() ?? '0');
    _kind = existing?.kind ?? RateKind.base;
    _weekdays = Set<int>.from(existing?.weekdays ?? const []);
    _validFrom = existing?.validFrom;
    _validTo = existing?.validTo;
  }

  @override
  void dispose() {
    _label.dispose();
    _price.dispose();
    _extraGuestPrice.dispose();
    _cleaningFee.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initialRange = (_validFrom != null && _validTo != null)
        ? DateTimeRange(start: _validFrom!, end: _validTo!)
        : null;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
      initialDateRange: initialRange,
    );
    if (picked != null) {
      setState(() {
        _validFrom = picked.start;
        _validTo = picked.end;
        _dateError = null;
      });
    }
  }

  void _clearDateRange() {
    setState(() {
      _validFrom = null;
      _validTo = null;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final dateError = validateRateRuleDates(
      kind: _kind,
      validFrom: _validFrom,
      validTo: _validTo,
    );
    if (dateError != null) {
      setState(() => _dateError = dateError);
      return;
    }

    setState(() {
      _busy = true;
      _dateError = null;
    });
    try {
      final existing = widget.existing;
      final label = _label.text.trim();
      final weekdays = _weekdays.toList()..sort();
      final rule = RateRule(
        id: existing?.id ?? '',
        unitId: widget.unitId,
        kind: _kind,
        label: label.isEmpty ? null : label,
        slotTypeId: existing?.slotTypeId,
        validFrom: _validFrom,
        validTo: _validTo,
        weekdays: weekdays,
        price: num.parse(_price.text),
        extraGuestPrice: num.tryParse(_extraGuestPrice.text) ?? 0,
        cleaningFee: num.tryParse(_cleaningFee.text) ?? 0,
        priority: int.tryParse(_priority.text) ?? 0,
      );
      await ref
          .read(rateRepositoryProvider)
          .upsert(rule, id: existing?.id);
      ref.invalidate(rateRulesProvider(widget.unitId));
      if (mounted) Navigator.of(context).pop();
    } on BookingFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'New rate rule' : 'Edit rate rule'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  SegmentedButton<RateKind>(
                    segments: [
                      for (final kind in RateKind.values)
                        ButtonSegment(value: kind, label: Text(_kindLabel(kind))),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (selection) => setState(() {
                      _kind = selection.first;
                      _dateError = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('rate-label'),
                    controller: _label,
                    decoration: const InputDecoration(
                      labelText: 'Label',
                      helperText: 'Optional, e.g. "Diwali season"',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('rate-price'),
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Price'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final price = num.tryParse(v ?? '');
                      if (price == null || price < 0) return 'Enter a price';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('rate-extra-guest-price'),
                    controller: _extraGuestPrice,
                    decoration:
                        const InputDecoration(labelText: 'Extra guest price'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final value = num.tryParse(v ?? '');
                      if (value == null || value < 0) return 'Enter an amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('rate-cleaning-fee'),
                    controller: _cleaningFee,
                    decoration: const InputDecoration(labelText: 'Cleaning fee'),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final value = num.tryParse(v ?? '');
                      if (value == null || value < 0) return 'Enter an amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('rate-priority'),
                    controller: _priority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final value = int.tryParse(v ?? '');
                      if (value == null) return 'Enter a whole number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    key: const Key('rate-date-range'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Valid date range'),
                    subtitle: Text(
                      (_validFrom != null && _validTo != null)
                          ? '${_dateFormat.format(_validFrom!)} – '
                              '${_dateFormat.format(_validTo!)}'
                          : (_kind == RateKind.override_
                              ? 'Required for overrides'
                              : 'Applies every day (optional)'),
                    ),
                    trailing: (_validFrom != null || _validTo != null)
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear date range',
                            onPressed: _clearDateRange,
                          )
                        : null,
                    onTap: _pickDateRange,
                  ),
                  if (_dateError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _dateError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text('Weekdays', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Leave all unselected to apply to every day.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          key: Key('weekday-$day'),
                          label: Text(_weekdayLabels[day - 1]),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(day);
                            } else {
                              _weekdays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

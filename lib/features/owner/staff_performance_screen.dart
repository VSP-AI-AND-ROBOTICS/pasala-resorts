import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/empty_state.dart';
import '../../data/models/app_user.dart';
import '../../data/models/staff_performance.dart';
import '../../data/repositories/staff_performance_repository.dart';
import '../../data/repositories/user_admin_repository.dart';

DateTimeRange _last30Days() {
  final now = DateTime.now();
  return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now);
}

/// `/owner/staff-performance` -- task completion, attendance and
/// punctuality per staff member, over a chosen date range. Mirrors
/// `TasksScreen`'s filter-bar shape (a staff picker sourced from
/// `adminProfilesProvider`, same as the Tasks admin screen), but the data
/// itself is entirely read-only: there is nothing to create, edit, or
/// delete here.
class StaffPerformanceScreen extends ConsumerStatefulWidget {
  const StaffPerformanceScreen({super.key});

  @override
  ConsumerState<StaffPerformanceScreen> createState() =>
      _StaffPerformanceScreenState();
}

class _StaffPerformanceScreenState extends ConsumerState<StaffPerformanceScreen> {
  String? _staffId;
  DateTimeRange _range = _last30Days();

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  @override
  Widget build(BuildContext context) {
    final filter = (staffId: _staffId, from: _range.start, to: _range.end);
    final summary = ref.watch(staffPerformanceProvider(filter));
    final profiles = ref.watch(adminProfilesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff performance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: profiles.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (list) {
                          final staffOrAbove =
                              list.where((p) => p.role != UserRole.customer).toList();
                          return DropdownButtonFormField<String?>(
                            key: const Key('performance-staff-picker'),
                            initialValue: _staffId,
                            decoration: const InputDecoration(labelText: 'Staff member'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All staff')),
                              for (final p in staffOrAbove)
                                DropdownMenuItem(
                                  value: p.id,
                                  child: Text(p.fullName ?? p.email),
                                ),
                            ],
                            onChanged: (value) => setState(() => _staffId = value),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('Range'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: AsyncView(
              value: summary,
              onRetry: () => ref.invalidate(staffPerformanceProvider(filter)),
              empty: () => const EmptyState(
                icon: Icons.leaderboard_outlined,
                title: 'No staff to show',
                message: 'Promote an account to staff or above from Users.',
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                children: [
                  for (final p in list) _PerformanceCard(performance: p),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.performance});

  final StaffPerformance performance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.person_outline, color: scheme.primary),
                ),
                const SizedBox(width: Spacing.sm),
                Text(
                  performance.staffName.isEmpty
                      ? performance.staffId
                      : performance.staffName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.lg,
              runSpacing: Spacing.xs,
              children: [
                _metric('Tasks', '${performance.tasksCompleted}/${performance.tasksAssigned}'),
                _metric('Completion', '${performance.completionRatePct}%'),
                _metric('Avg. completion', '${performance.avgCompletionHours}h'),
                _metric('Days present', '${performance.daysPresent}'),
                _metric('Leave days', '${performance.leaveDaysApproved}'),
                _metric('Avg. check-in delay', '${performance.avgCheckinDelayMinutes}m'),
              ].map((w) => DefaultTextStyle.merge(
                    style: TextStyle(color: scheme.onSurfaceVariant),
                    child: w,
                  )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      );
}

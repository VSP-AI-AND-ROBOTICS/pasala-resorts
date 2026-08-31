import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

/// A stand-in for a staff-hub section that has no screen yet (Working
/// Hours, Leave Management, Assigned Work, Work Schedules, Time Slots,
/// Daily Work Status) -- each gets its own design and data model in a
/// later task. Parameterised by [title]/[icon] so one screen serves all of
/// them until they're built out individually.
class PlaceholderSectionScreen extends StatelessWidget {
  const PlaceholderSectionScreen({
    super.key,
    required this.title,
    required this.icon,
  });

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: EmptyState(
          icon: icon,
          title: title,
          message: 'Coming soon in a future update.',
        ),
      );
}

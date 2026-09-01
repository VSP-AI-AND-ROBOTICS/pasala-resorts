import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/async_view.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/repositories/review_repository.dart';

/// Five sub-ratings plus overall and free-text feedback, one-time per
/// reservation (`reviews.reservation_id` is unique and the RLS insert
/// policy requires `status = 'checked_out'`).
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _farmhouse = 5;
  int _cleanliness = 5;
  int _food = 5;
  int _service = 5;
  int _activities = 5;
  int _overall = 5;
  final _feedbackController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(reviewRepositoryProvider).submit(
            reservationId: widget.reservationId,
            farmhouseRating: _farmhouse,
            cleanlinessRating: _cleanliness,
            foodRating: _food,
            serviceRating: _service,
            activitiesRating: _activities,
            overallRating: _overall,
            feedback: _feedbackController.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(reviewForReservationProvider(widget.reservationId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Thank you for your feedback')));
      context.go('/bookings');
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stars(String label, int value, ValueChanged<int> onChanged) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            for (var i = 1; i <= 5; i++)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(i <= value ? Icons.star : Icons.star_border),
                onPressed: () => onChanged(i),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final existingAsync = ref.watch(reviewForReservationProvider(widget.reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Review Your Stay')),
      body: AsyncView(
        value: existingAsync,
        data: (existing) {
          if (existing != null) {
            return const Padding(
              padding: EdgeInsets.all(Spacing.md),
              child: Center(child: Text('You already reviewed this stay. Thank you!')),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(Spacing.md),
            children: [
              _stars('Farmhouse', _farmhouse, (v) => setState(() => _farmhouse = v)),
              _stars('Cleanliness', _cleanliness, (v) => setState(() => _cleanliness = v)),
              _stars('Food', _food, (v) => setState(() => _food = v)),
              _stars('Service', _service, (v) => setState(() => _service = v)),
              _stars('Activities', _activities, (v) => setState(() => _activities = v)),
              _stars('Overall', _overall, (v) => setState(() => _overall = v)),
              const SizedBox(height: Spacing.md),
              TextField(
                controller: _feedbackController,
                decoration: const InputDecoration(labelText: 'Tell us more (optional)'),
                maxLines: 4,
              ),
              const SizedBox(height: Spacing.lg),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Submitting…' : 'Submit review'),
              ),
            ],
          );
        },
      ),
    );
  }
}

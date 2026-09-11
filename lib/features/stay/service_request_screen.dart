import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/service_request.dart';
import '../../data/repositories/service_request_repository.dart';

/// New service request form + a link out to the customer's existing
/// requests -- mirrors [FoodMenuScreen]'s "browse + link to my own list"
/// shape.
class ServiceRequestScreen extends ConsumerStatefulWidget {
  const ServiceRequestScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends ConsumerState<ServiceRequestScreen> {
  ServiceRequestCategory _category = ServiceRequestCategory.cleaning;
  final _descriptionController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(serviceRequestRepositoryProvider).create(
            reservationId: widget.reservationId,
            category: _category,
            description: _descriptionController.text.trim(),
          );
      if (!mounted) return;
      ref.invalidate(myServiceRequestsProvider(widget.reservationId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Request sent')));
      context.pop();
    } on BookingFailure catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(FailureView.messageFor(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Request'),
        actions: [
          IconButton(
            tooltip: 'My requests',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => context.push('/my-stay/service-requests/mine',
                extra: widget.reservationId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          for (final category in ServiceRequestCategory.values)
            RadioListTile<ServiceRequestCategory>(
              contentPadding: EdgeInsets.zero,
              title: Text(serviceRequestCategoryLabel(category)),
              value: category,
              groupValue: _category,
              onChanged: (value) => setState(() => _category = value!),
            ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Details (optional)'),
            maxLines: 3,
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Sending…' : 'Send request'),
          ),
        ],
      ),
    );
  }
}

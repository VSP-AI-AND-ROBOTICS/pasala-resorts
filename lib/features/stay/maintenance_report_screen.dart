import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/failure_view.dart';
import '../../data/models/maintenance_issue.dart';
import '../../data/repositories/maintenance_repository.dart';

class MaintenanceReportScreen extends ConsumerStatefulWidget {
  const MaintenanceReportScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  ConsumerState<MaintenanceReportScreen> createState() =>
      _MaintenanceReportScreenState();
}

class _MaintenanceReportScreenState extends ConsumerState<MaintenanceReportScreen> {
  MaintenanceCategory _category = MaintenanceCategory.ac;
  MaintenancePriority _priority = MaintenancePriority.medium;
  final _descriptionController = TextEditingController();
  XFile? _photo;
  bool _busy = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _photo = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      String? photoUrl;
      final photo = _photo;
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        photoUrl = await ref.read(maintenanceRepositoryProvider).uploadPhoto(
              filename: photo.name,
              bytes: Uint8List.fromList(bytes),
              contentType: photo.mimeType ?? 'image/jpeg',
            );
      }
      await ref.read(maintenanceRepositoryProvider).report(
            reservationId: widget.reservationId,
            category: _category,
            description: _descriptionController.text.trim(),
            photoUrl: photoUrl,
            priority: _priority,
          );
      if (!mounted) return;
      ref.invalidate(myMaintenanceIssuesProvider(widget.reservationId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Issue reported')));
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
        title: const Text('Report an Issue'),
        actions: [
          IconButton(
            tooltip: 'My reports',
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => context.push('/my-stay/maintenance/mine',
                extra: widget.reservationId),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          DropdownButtonFormField<MaintenanceCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in MaintenanceCategory.values)
                DropdownMenuItem(value: c, child: Text(maintenanceCategoryLabel(c))),
            ],
            onChanged: (value) => setState(() => _category = value!),
          ),
          const SizedBox(height: Spacing.md),
          DropdownButtonFormField<MaintenancePriority>(
            initialValue: _priority,
            decoration: const InputDecoration(labelText: 'Priority'),
            items: [
              for (final p in MaintenancePriority.values)
                DropdownMenuItem(value: p, child: Text(maintenancePriorityLabel(p))),
            ],
            onChanged: (value) => setState(() => _priority = value!),
          ),
          const SizedBox(height: Spacing.md),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Describe the issue'),
            maxLines: 3,
          ),
          const SizedBox(height: Spacing.md),
          OutlinedButton.icon(
            onPressed: _pickPhoto,
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(_photo == null ? 'Add a photo (optional)' : _photo!.name),
          ),
          const SizedBox(height: Spacing.lg),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Submitting…' : 'Submit report'),
          ),
        ],
      ),
    );
  }
}

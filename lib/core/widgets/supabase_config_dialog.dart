import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/supabase_service.dart';

class SupabaseConfigDialog extends StatefulWidget {
  const SupabaseConfigDialog({super.key});

  @override
  State<SupabaseConfigDialog> createState() => _SupabaseConfigDialogState();
}

class _SupabaseConfigDialogState extends State<SupabaseConfigDialog> {
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: AppConfig.supabaseUrl);
    _keyController = TextEditingController(text: AppConfig.supabaseAnonKey);
  }

  void _saveConfig() async {
    setState(() => _isSaving = true);

    AppConfig.supabaseUrl = _urlController.text.trim();
    AppConfig.supabaseAnonKey = _keyController.text.trim();

    await SupabaseService.instance.initialize(
      supabaseUrl: AppConfig.supabaseUrl,
      supabaseAnonKey: AppConfig.supabaseAnonKey,
    );

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            SupabaseService.instance.isOnline
                ? 'Connected to Live Supabase Project!'
                : 'Supabase credentials saved. Operating mode updated.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.cloud_sync, color: Colors.teal),
          SizedBox(width: 8),
          Text('Live Supabase Configuration'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Connect ResortHub directly to your live Supabase backend by supplying your Project URL and Anon Key.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Supabase Project URL',
                hintText: 'https://your-project.supabase.co',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              decoration: const InputDecoration(
                labelText: 'Supabase Anon API Key',
                hintText: 'eyJhbGciOi...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveConfig,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
          child: _isSaving
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Text('Connect Live Supabase'),
        ),
      ],
    );
  }
}

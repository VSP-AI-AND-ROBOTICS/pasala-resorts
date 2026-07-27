import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends StatelessWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Pasala Resorts',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Scaffold(body: Center(child: Text('Pasala'))),
      );
}

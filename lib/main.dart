import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends ConsumerWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'Pasala Resorts',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) =>
            AppSplashOverlay(child: child ?? const SizedBox()),
      );
}

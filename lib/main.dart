import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/e2e_semantics.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/widgets/app_splash_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No effect unless built with --dart-define=E2E=true (e2e/build-app.sh).
  ensureE2eSemantics();
  await initSupabase();
  runApp(const ProviderScope(child: PasalaApp()));
}

class PasalaApp extends ConsumerWidget {
  const PasalaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'ResortHub',
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        routerConfig: ref.watch(routerProvider),
        builder: (context, child) =>
            AppSplashOverlay(child: child ?? const SizedBox()),
      );
}

import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/supabase_service.dart';
import 'core/widgets/mobile_frame_wrapper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (with automatic graceful fallback to Mock store)
  await SupabaseService.instance.initialize();

  runApp(const ResortHubApp());
}

class ResortHubApp extends StatelessWidget {
  const ResortHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp.router(
          title: 'ResortHub',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          routerConfig: AppRouter.router,
          builder: (context, child) => MobileFrameWrapper(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

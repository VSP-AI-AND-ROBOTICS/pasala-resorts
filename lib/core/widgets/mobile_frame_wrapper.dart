import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class MobileFrameWrapper extends StatefulWidget {
  final Widget child;

  const MobileFrameWrapper({super.key, required this.child});

  @override
  State<MobileFrameWrapper> createState() => _MobileFrameWrapperState();
}

class _MobileFrameWrapperState extends State<MobileFrameWrapper> {
  bool _isMobileFrameActive = true; // Default ON: Mobile App First View

  void toggleMobileFrame() {
    setState(() {
      _isMobileFrameActive = !_isMobileFrameActive;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        if (_isMobileFrameActive)
          Container(
            color: isDark ? const Color(0xFF020617) : const Color(0xFF0F172A), // Dark slate backdrop
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Container(
                    width: 390,
                    height: 844,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : AppTheme.bookingBgLight,
                      borderRadius: BorderRadius.circular(44),
                      border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFF334155), width: 10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 36,
                          spreadRadius: 4,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        // Main App Canvas inside Mobile Viewport (with top inset for notch)
                        Positioned.fill(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 36, bottom: 8),
                            child: widget.child,
                          ),
                        ),

                        // Smartphone Camera Notch / Pill
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 8),
                              width: 120,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF1E293B),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF0F172A),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Home Indicator Bar
                        Positioned(
                          bottom: 6,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              width: 130,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          widget.child,

        // Floating Controls (Top Right: Theme Toggle & Viewport Toggle)
        Positioned(
          top: 16,
          right: 16,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Light / Dark Theme Toggle Button
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppTheme.themeNotifier,
                    builder: (ctx, currentMode, _) {
                      final isDark = currentMode == ThemeMode.dark;
                      return InkWell(
                        onTap: AppTheme.toggleTheme,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF334155) : Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                          ),
                          child: Row(
                            children: [
                              Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: isDark ? Colors.amber : Colors.orange, size: 18),
                              const SizedBox(width: 4),
                              Text(
                                isDark ? 'Dark' : 'Light',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  // Web / Mobile Viewport Toggle
                  InkWell(
                    onTap: toggleMobileFrame,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isMobileFrameActive ? AppTheme.bookingYellow : AppTheme.bookingNavy,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isMobileFrameActive ? Icons.desktop_windows : Icons.smartphone,
                            color: _isMobileFrameActive ? AppTheme.bookingNavy : Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isMobileFrameActive ? 'Web' : 'Mobile',
                            style: TextStyle(
                              color: _isMobileFrameActive ? AppTheme.bookingNavy : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

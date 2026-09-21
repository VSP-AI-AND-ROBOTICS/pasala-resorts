import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user_profile.dart';
import '../services/mock_data_store.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'supabase_config_dialog.dart';

class RoleSwitcherBar extends StatelessWidget {
  const RoleSwitcherBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = MockDataStore.instance;
    final currentRole = store.currentUser?.role ?? AppRole.superAdmin;
    final isOnline = SupabaseService.instance.isOnline;

    return Container(
      color: Colors.indigo.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => const SupabaseConfigDialog(),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green.shade800 : Colors.amber.shade900,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(isOnline ? Icons.cloud_done : Icons.cloud_off, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      isOnline ? 'LIVE SUPABASE' : 'CONNECT SUPABASE',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: AppTheme.themeNotifier,
              builder: (ctx, currentMode, _) {
                final isDark = currentMode == ThemeMode.dark;
                return InkWell(
                  onTap: AppTheme.toggleTheme,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFFEBB02),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: isDark ? Colors.amber : const Color(0xFF003580), size: 14),
                        const SizedBox(width: 4),
                        Text(
                          isDark ? 'DARK MODE' : 'LIGHT MODE',
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF003580),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 12),
            const Icon(Icons.swap_horiz, color: Colors.cyanAccent, size: 18),
            const SizedBox(width: 6),
            const Text(
              'ROLE SWITCHER:',
              style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
            ),
            const SizedBox(width: 12),
            _buildRoleChip(
              context,
              role: AppRole.superAdmin,
              label: 'Co-owner / Super Admin',
              email: 'owner@resorthub.com',
              route: '/super-admin',
              isSelected: currentRole == AppRole.superAdmin,
            ),
            const SizedBox(width: 8),
            _buildRoleChip(
              context,
              role: AppRole.admin,
              label: 'Resort Admin',
              email: 'admin@grandpalms.com',
              route: '/admin',
              isSelected: currentRole == AppRole.admin,
            ),
            const SizedBox(width: 8),
            _buildRoleChip(
              context,
              role: AppRole.incharge,
              label: 'Incharge (Ops)',
              email: 'incharge@grandpalms.com',
              route: '/incharge',
              isSelected: currentRole == AppRole.incharge,
            ),
            const SizedBox(width: 8),
            _buildRoleChip(
              context,
              role: AppRole.accountant,
              label: 'Accountant',
              email: 'accountant@grandpalms.com',
              route: '/accountant',
              isSelected: currentRole == AppRole.accountant,
            ),
            const SizedBox(width: 8),
            _buildRoleChip(
              context,
              role: AppRole.customer,
              label: 'Customer',
              email: 'customer@example.com',
              route: '/customer',
              isSelected: currentRole == AppRole.customer,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleChip(
    BuildContext context, {
    required AppRole role,
    required String label,
    required String email,
    required String route,
    required bool isSelected,
  }) {
    final store = MockDataStore.instance;

    return InkWell(
      onTap: () {
        store.authenticate(email, 'password123');
        context.go(route);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

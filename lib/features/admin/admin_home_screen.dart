import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// `/admin` landing page. Reachable only by `isAdmin` users -- the router
/// redirects everyone else to `/404`, and `properties_write`/`units_write`
/// RLS policies are the real enforcement underneath.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.home_work_outlined),
              title: const Text('Properties'),
              onTap: () => context.go('/admin/properties'),
            ),
            ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: const Text('All bookings'),
              onTap: () => context.go('/admin/bookings'),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt_outlined),
              title: const Text('Today'),
              onTap: () => context.go('/staff'),
            ),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  final MockDataStore _store = MockDataStore.instance;

  @override
  Widget build(BuildContext context) {
    final user = _store.currentUser;
    final isDark = AppTheme.isDark(context);

    final customerRes = _store.reservations.where((r) {
      if (user == null) return false;
      return r.customerId == user.id || r.guestEmail.trim().toLowerCase() == user.email.trim().toLowerCase();
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.cardBg(context),
        foregroundColor: AppTheme.textPrimary(context),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border(context)),
        ),
        title: Text(
          'My Resort Passes & Bookings',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary(context)),
        ),
      ),
      body: customerRes.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.confirmation_number_outlined, size: 64, color: AppTheme.textMuted(context)),
                  const SizedBox(height: 12),
                  Text(
                    'No active or past bookings found.',
                    style: TextStyle(color: AppTheme.textMuted(context), fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: customerRes.length,
              itemBuilder: (context, index) {
                final r = customerRes[index];
                final resort = _store.resorts[r.resortId];

                final isConfirmed = r.status.displayName.toLowerCase().contains('confirm');
                final isPending = r.status.displayName.toLowerCase().contains('pend');
                final badgeGradient = isConfirmed
                    ? const [Color(0xFF059669), Color(0xFF10B981)]
                    : (isPending
                        ? const [Color(0xFFD97706), Color(0xFFF59E0B)]
                        : const [Color(0xFFDC2626), Color(0xFFEF4444)]);

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Ticket Header Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF121E19) : const Color(0xFF1C1917),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  const Icon(Icons.confirmation_number, color: Color(0xFFFBBF24), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'PASS ID: ${r.id.toUpperCase()}',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: badgeGradient),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
                                ],
                              ),
                              child: Text(
                                r.status.displayName.toUpperCase(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        resort?.name ?? 'Resort Stay',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary(context)),
                                      ),
                                      const SizedBox(height: 4),
                                      if (resort != null)
                                        InkWell(
                                          onTap: () async {
                                            final queryParts = [resort.name, resort.address, resort.city, resort.state]
                                                .where((s) => s.trim().isNotEmpty)
                                                .join(', ');
                                            final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': queryParts});
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                                            } else {
                                              await launchUrl(uri);
                                            }
                                          },
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.location_on, size: 14, color: AppTheme.resortEmerald),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${resort.city}, ${resort.state}',
                                                style: const TextStyle(
                                                  color: AppTheme.resortEmerald,
                                                  fontSize: 13,
                                                  decoration: TextDecoration.underline,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.open_in_new, size: 11, color: AppTheme.resortEmerald),
                                            ],
                                          ),
                                        )
                                      else
                                        Text('Location information unavailable', style: TextStyle(color: AppTheme.textMuted(context), fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Divider(height: 24, color: AppTheme.border(context)),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('CHECK-IN', style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context), fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(r.checkIn.toString().split(' ')[0], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary(context))),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('CHECK-OUT', style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context), fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(r.checkOut.toString().split(' ')[0], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textPrimary(context))),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('TOTAL AMOUNT', style: TextStyle(fontSize: 10, color: AppTheme.textMuted(context), fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      '₹${r.totalAmount.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.resortEmerald),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF13382B) : const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? const Color(0xFF1E5240) : const Color(0xFFA7F3D0)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle, color: isDark ? const Color(0xFF6EE7B7) : AppTheme.resortDarkGreen, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Advance Paid: ₹${r.advanceAmount.toStringAsFixed(2)} • Pass Confirmed',
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFFD1FAE5) : AppTheme.resortDarkGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }
}

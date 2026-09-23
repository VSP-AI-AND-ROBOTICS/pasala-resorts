import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/resort.dart';
import '../../core/models/unit.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import 'booking_flow_dialog.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class ResortDetailPage extends StatefulWidget {
  final String resortId;

  const ResortDetailPage({super.key, required this.resortId});

  @override
  State<ResortDetailPage> createState() => _ResortDetailPageState();
}

class _ResortDetailPageState extends State<ResortDetailPage> {
  int _currentImageIndex = 0;
  bool _isFavorite = false;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openGoogleMaps(Resort resort) async {
    final queryParts = [resort.name, resort.address, resort.city, resort.state]
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final uri = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': queryParts});
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not launch Google Maps: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = MockDataStore.instance;
    final resort = store.resorts[widget.resortId];
    final isDark = AppTheme.isDark(context);

    if (resort == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Property Not Found')),
        body: const Center(child: Text('Requested resort property is unavailable.')),
      );
    }

    final rawUnits = store.resortUnits[widget.resortId] ?? [];
    final units = rawUnits.isNotEmpty
        ? rawUnits
        : [
            ResortUnit(
              id: 'unit-default-${resort.id}',
              resortId: resort.id,
              name: 'Standard Guest Room',
              type: 'room',
              capacity: 2,
              pricePerNight: 120.00,
              description: 'Comfortable guest room with air conditioning, ensuite bath, and free Wi-Fi.',
              status: 'available',
              amenities: const ['Air Conditioning', 'Free Wi-Fi', 'Ensuite Bath'],
              imageUrls: const [],
            )
          ];

    final primaryUnit = units.first;
    final images = resort.imageUrls.isNotEmpty
        ? resort.imageUrls
        : [
            'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=900&auto=format&fit=crop&q=80',
            'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=900&auto=format&fit=crop&q=80',
          ];

    final coreAmenities = [
      {'icon': Icons.wifi_rounded, 'label': 'Wi-Fi'},
      {'icon': Icons.restaurant_rounded, 'label': 'Breakfast'},
      {'icon': Icons.local_parking_rounded, 'label': 'Free Parking'},
      {'icon': Icons.pool_rounded, 'label': 'Pool'},
    ];

    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full-width Hero Image with Rounded Bottom Corners
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  child: SizedBox(
                    height: 320,
                    width: double.infinity,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: images.length,
                      onPageChanged: (idx) => setState(() => _currentImageIndex = idx),
                      itemBuilder: (ctx, idx) {
                        return Image.network(
                          images[idx],
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(
                            color: const Color(0xFF0F3E36),
                            child: const Center(
                              child: Icon(Icons.hotel_rounded, size: 64, color: Colors.white70),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                // Top Buttons Row (Back & Favorite)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF1E2E28) : Colors.white).withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.border(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppTheme.textPrimary(context)),
                          onPressed: () {
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            } else {
                              context.go('/customer');
                            }
                          },
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: (isDark ? const Color(0xFF1E2E28) : Colors.white).withValues(alpha: 0.95),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.border(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 20,
                            color: _isFavorite ? Colors.redAccent : AppTheme.textPrimary(context),
                          ),
                          onPressed: () {
                            setState(() => _isFavorite = !_isFavorite);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom-right Photo Index Badge
                Positioned(
                  bottom: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${_currentImageIndex + 1}/${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Content Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Capacity
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resort.name,
                              style: TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E2E28) : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.border(context)),
                              ),
                              child: Text(
                                '2 Adults • 1 Child',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMuted(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Rating & Reviews Row
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 20, color: AppTheme.resortGold),
                      const SizedBox(width: 4),
                      Text(
                        '${resort.rating}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(1,480 reviews)',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Location & Google Maps Redirection
                  InkWell(
                    onTap: () => _openGoogleMaps(resort),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.resortEmerald),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${resort.address}, ${resort.city}, ${resort.state}',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted(context),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF13382B) : AppTheme.resortSoftGreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Maps',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF6EE7B7) : AppTheme.resortDarkGreen),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.open_in_new_rounded, size: 12, color: isDark ? const Color(0xFF6EE7B7) : AppTheme.resortDarkGreen),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 4 Core Amenity Cards
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: coreAmenities.map((amenity) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg(context),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppTheme.border(context)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  amenity['icon'] as IconData,
                                  color: AppTheme.resortEmerald,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                amenity['label'] as String,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary(context),
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 26),

                  // About Section
                  Text(
                    'About this resort',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    resort.description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.6,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // Property Amenities
                  Text(
                    'Property amenities',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: resort.amenities.map((amenity) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border(context)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 14, color: AppTheme.resortEmerald),
                            const SizedBox(width: 6),
                            Text(
                              amenity,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // Room Selection
                  Text(
                    'Available Rooms',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...units.map((unit) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border(context)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  unit.name,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                              ),
                              Text(
                                '₹${unit.pricePerNight.toStringAsFixed(0)}/night',
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.resortEmerald,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            unit.description,
                            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 38,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                              ),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (ctx) => BookingFlowDialog(resort: resort, unit: unit),
                                );
                              },
                              child: const Text('Book this Room', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),

      // Screen 3: Premium Sticky Bottom Booking Card
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          border: Border(top: BorderSide(color: AppTheme.border(context), width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF13382B) : AppTheme.resortSoftGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Member Exclusive',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF6EE7B7) : AppTheme.resortDarkGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Book Now, Pay Later • Free cancellation',
                    style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Total Price',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context), fontWeight: FontWeight.w500),
                      ),
                      Row(
                        children: [
                          Text(
                            '₹${primaryUnit.pricePerNight.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary(context),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '/night',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => BookingFlowDialog(resort: resort, unit: primaryUnit),
                        );
                      },
                      child: const Text(
                        'Book Room',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/resort.dart';
import '../../core/services/mock_data_store.dart';
import '../../core/theme/app_theme.dart';
import '../discovery/services/location_service.dart';
import 'my_bookings_page.dart';
import '../../core/widgets/ai_assistant_dialog.dart';

class CustomerHomePage extends StatefulWidget {
  const CustomerHomePage({super.key});

  @override
  State<CustomerHomePage> createState() => _CustomerHomePageState();
}

class _CustomerHomePageState extends State<CustomerHomePage> {
  final MockDataStore _store = MockDataStore.instance;
  final LocationService _locationService = LocationService.instance;

  final String _searchQuery = '';
  String _selectedCity = 'All Locations';
  int _currentNavIndex = 0;
  bool _isSearching = false; // Toggles between Screen 1 (Discover) & Screen 2 (Search Results)

  final Set<String> _selectedAmenities = {};
  final Set<String> _favoriteResortIds = {};

  static const List<Map<String, dynamic>> _amenityFilters = [
    {
      'name': 'Free Wi-Fi',
      'icon': Icons.wifi_rounded,
      'keyword': 'wifi',
    },
    {
      'name': 'Swimming Pool',
      'icon': Icons.pool_rounded,
      'keyword': 'pool',
    },
    {
      'name': 'Luxury Spa',
      'icon': Icons.spa_rounded,
      'keyword': 'spa',
    },
    {
      'name': 'Restaurant',
      'icon': Icons.restaurant_rounded,
      'keyword': 'restaurant',
    },
    {
      'name': 'Free Parking',
      'icon': Icons.local_parking_rounded,
      'keyword': 'park',
    },
    {
      'name': 'Air Conditioning',
      'icon': Icons.ac_unit_rounded,
      'keyword': 'ac',
    },
    {
      'name': 'Beach Access',
      'icon': Icons.beach_access_rounded,
      'keyword': 'beach',
    },
    {
      'name': 'Scenic View',
      'icon': Icons.landscape_rounded,
      'keyword': 'view',
    },
  ];

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
  void initState() {
    super.initState();
    _detectUserLocationCity();
  }

  void _detectUserLocationCity() {
    final resorts = _store.resorts.values.toList();
    final detected = _locationService.detectNearestCity(
      userLocation: _locationService.defaultUserPosition,
      resorts: resorts,
    );
    setState(() {
      _selectedCity = detected;
    });
  }

  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now(),
    end: DateTime.now().add(const Duration(days: 3)),
  );
  int _adultsCount = 2;
  int _childrenCount = 1;
  int _roomsCount = 1;

  final List<Map<String, dynamic>> _popularDestinations = [
    {'name': 'All Locations', 'icon': Icons.all_inclusive_rounded},
    {'name': 'Goa', 'icon': Icons.beach_access_rounded},
    {'name': 'Hyderabad', 'icon': Icons.location_city_rounded},
    {'name': 'Munnar', 'icon': Icons.terrain_rounded},
    {'name': 'Udaipur', 'icon': Icons.castle_rounded},
    {'name': 'Shimla', 'icon': Icons.ac_unit_rounded},
    {'name': 'Kumarakom', 'icon': Icons.water_rounded},
    {'name': 'Kabini', 'icon': Icons.forest_rounded},
  ];

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]}';
  }

  String get _dateRangeText {
    return '${_formatDate(_dateRange.start)} – ${_formatDate(_dateRange.end)}';
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: AppTheme.isDark(context) ? AppTheme.darkTheme : AppTheme.lightTheme,
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  void _openGuestPicker() {
    final isDark = AppTheme.isDark(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Select Guests & Rooms',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: AppTheme.textPrimary(context)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Divider(height: 24, color: AppTheme.border(context)),
                  _buildCounterRow(
                    title: 'Rooms',
                    subtitle: 'Number of rooms needed',
                    value: _roomsCount,
                    onDecrement: _roomsCount > 1
                        ? () {
                            setState(() => _roomsCount--);
                            setModalState(() {});
                          }
                        : null,
                    onIncrement: _roomsCount < 10
                        ? () {
                            setState(() => _roomsCount++);
                            setModalState(() {});
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildCounterRow(
                    title: 'Adults',
                    subtitle: 'Ages 18 or above',
                    value: _adultsCount,
                    onDecrement: _adultsCount > 1
                        ? () {
                            setState(() => _adultsCount--);
                            setModalState(() {});
                          }
                        : null,
                    onIncrement: _adultsCount < 30
                        ? () {
                            setState(() => _adultsCount++);
                            setModalState(() {});
                          }
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildCounterRow(
                    title: 'Children',
                    subtitle: 'Ages 0 to 17',
                    value: _childrenCount,
                    onDecrement: _childrenCount > 0
                        ? () {
                            setState(() => _childrenCount--);
                            setModalState(() {});
                          }
                        : null,
                    onIncrement: _childrenCount < 10
                        ? () {
                            setState(() => _childrenCount++);
                            setModalState(() {});
                          }
                        : null,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Apply Selection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCounterRow({
    required String title,
    required String subtitle,
    required int value,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
            Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.textMuted(context))),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: onDecrement,
              icon: Icon(Icons.remove_circle_outline, color: onDecrement != null ? AppTheme.textPrimary(context) : Colors.grey.shade600),
            ),
            Text(
              '$value',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
            ),
            IconButton(
              onPressed: onIncrement,
              icon: Icon(Icons.add_circle_outline, color: onIncrement != null ? AppTheme.textPrimary(context) : Colors.grey.shade600),
            ),
          ],
        ),
      ],
    );
  }

  void _openLocationPicker() {
    final cities = [
      'All Locations',
      'Hyderabad',
      'Goa',
      'Munnar',
      'Kumarakom',
      'Udaipur',
      'Kovalam',
      'Shimla',
      'Kabini',
      'Lonavala',
      'Manali',
      'Ranthambore',
      'Mussoorie',
      'Alleppey',
      'Ooty',
      'Kodaikanal',
      'Wayanad',
      'Rishikesh',
      'Jaisalmer',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Select Destination', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
                  IconButton(icon: Icon(Icons.close_rounded, color: AppTheme.textPrimary(context)), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.my_location_rounded, color: AppTheme.resortEmerald),
                title: const Text('Detect Current Location', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.resortEmerald)),
                subtitle: Text('Auto-detect nearest resort destination via GPS', style: TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                tileColor: AppTheme.isDark(context) ? const Color(0xFF192A23) : AppTheme.resortSoftGreen.withValues(alpha: 0.5),
                onTap: () {
                  _detectUserLocationCity();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('📍 Nearest destination: $_selectedCity'),
                      backgroundColor: AppTheme.isDark(context) ? const Color(0xFF1F352C) : AppTheme.resortBlack,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppTheme.border(context)),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cities.length,
                  itemBuilder: (context, index) {
                    final city = cities[index];
                    final isSelected = _selectedCity == city;

                    return ListTile(
                      leading: Icon(
                        city == 'All Locations' ? Icons.map_rounded : Icons.location_city_rounded,
                        color: isSelected ? AppTheme.resortEmerald : AppTheme.textMuted(context),
                      ),
                      title: Text(
                        city,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? AppTheme.resortEmerald : AppTheme.textPrimary(context),
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppTheme.resortEmerald) : null,
                      onTap: () {
                        setState(() {
                          _selectedCity = city;
                          _isSearching = true;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openFilterDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filter Properties', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedAmenities.clear());
                          setModalState(() {});
                        },
                        child: const Text('Reset All', style: TextStyle(color: AppTheme.resortEmerald, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  Divider(height: 16, color: AppTheme.border(context)),
                  Text('Amenities', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _amenityFilters.map((f) {
                      final name = f['name'] as String;
                      final isSelected = _selectedAmenities.contains(name);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(name),
                        avatar: Icon(f['icon'] as IconData, size: 16, color: isSelected ? Colors.white : AppTheme.textPrimary(context)),
                        selectedColor: AppTheme.resortEmerald,
                        backgroundColor: AppTheme.pillBg(context),
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: isSelected ? Colors.transparent : AppTheme.border(context)),
                        ),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedAmenities.add(name);
                            } else {
                              _selectedAmenities.remove(name);
                            }
                          });
                          setModalState(() {});
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.isDark(context) ? AppTheme.resortEmerald : AppTheme.resortBlack,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Apply Filters', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    final rawResorts = _store.resorts.values.where((r) {
      bool matchesCity = true;
      if (_selectedCity != 'All Locations') {
        final queryCity = _selectedCity.toLowerCase();
        matchesCity = r.city.toLowerCase().contains(queryCity) ||
            r.state.toLowerCase().contains(queryCity) ||
            r.name.toLowerCase().contains(queryCity) ||
            r.address.toLowerCase().contains(queryCity);
      }

      final matchesSearch = r.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          r.city.toLowerCase().contains(_searchQuery.toLowerCase());

      bool matchesAmenities = true;
      if (_selectedAmenities.isNotEmpty) {
        matchesAmenities = _selectedAmenities.every((filterName) {
          final filter = _amenityFilters.firstWhere(
            (f) => f['name'] == filterName,
            orElse: () => {'keyword': filterName.toLowerCase()},
          );
          final keyword = (filter['keyword'] as String).toLowerCase();
          return r.amenities.any((a) {
            final aLower = a.toLowerCase();
            if (keyword == 'wifi') return aLower.contains('wi-fi') || aLower.contains('wifi');
            if (keyword == 'pool') return aLower.contains('pool');
            if (keyword == 'spa') return aLower.contains('spa') || aLower.contains('wellness');
            if (keyword == 'restaurant') return aLower.contains('restaurant') || aLower.contains('dining');
            if (keyword == 'park') return aLower.contains('park');
            if (keyword == 'ac') return aLower.contains('ac') || aLower.contains('air condition');
            if (keyword == 'beach') return aLower.contains('beach');
            if (keyword == 'view') return aLower.contains('view') || aLower.contains('mountain') || aLower.contains('lake');
            return aLower.contains(keyword);
          });
        });
      }

      return matchesCity && matchesSearch && matchesAmenities;
    }).toList();

    final sortedResorts = _locationService.sortResorts(
      resorts: rawResorts,
      userLocation: _locationService.defaultUserPosition,
    );

    return Scaffold(
      backgroundColor: AppTheme.pageBg(context),
      body: SafeArea(
        child: _currentNavIndex == 1
            ? const MyBookingsPage()
            : (_currentNavIndex == 2
                ? _buildMobileAccountView()
                : (_isSearching
                    ? _buildSearchResultsView(sortedResorts)
                    : _buildDiscoverView(sortedResorts))),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardBg(context),
          border: Border(top: BorderSide(color: AppTheme.border(context), width: 1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          selectedItemColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
          unselectedItemColor: AppTheme.textMuted(context),
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          backgroundColor: AppTheme.cardBg(context),
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() {
              _currentNavIndex = index;
              if (index == 0) {
                _isSearching = false;
              }
            });
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.explore_rounded), label: 'Explore'),
            BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_outlined), label: 'Bookings'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
          ],
        ),
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  // ==========================================
  // SCREEN 1: HOME / DISCOVER
  // ==========================================
  Widget _buildDiscoverView(List<Resort> resorts) {
    final user = _store.currentUser;
    final firstName = user != null && user.fullName.isNotEmpty ? user.fullName.split(' ').first : 'Traveler';
    final isDark = AppTheme.isDark(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Greeting & Notification
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi, $firstName 👋',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary(context),
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Where do you want to stay?',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textMuted(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.notifications_none_rounded, color: AppTheme.textPrimary(context), size: 22),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No new notifications right now.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Search Bar Capsule
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => setState(() => _isSearching = true),
            child: Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg(context),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.border(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: AppTheme.textPrimary(context), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedCity != 'All Locations' ? 'Stays in $_selectedCity' : 'Where do you want to stay?',
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedCity != 'All Locations' ? AppTheme.textPrimary(context) : AppTheme.textMuted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF22352C) : AppTheme.resortMintBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.tune_rounded, color: isDark ? AppTheme.resortEmerald : AppTheme.resortDarkText, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Hero Banner Card ("Escape The Ordinary")
          Container(
            height: 185,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=900&auto=format&fit=crop&q=80',
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      color: const Color(0xFF0F3E36),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.black.withValues(alpha: 0.35),
                          Colors.transparent,
                        ],
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'Escape The Ordinary',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Find exclusive resort deals worldwide',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 36,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppTheme.resortBlack,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                            onPressed: () => setState(() => _isSearching = true),
                            child: const Text(
                              'Explore Now',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),

          // Popular Destinations Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _popularDestinations.map((dest) {
                final name = dest['name'] as String;
                final isSelected = _selectedCity == name;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _selectedCity = name;
                        _isSearching = true;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? AppTheme.resortEmerald : AppTheme.resortBlack)
                            : AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : AppTheme.border(context),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            dest['icon'] as IconData,
                            size: 14,
                            color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 26),

          // "Featured Offers" Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Featured Offers',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary(context),
                  letterSpacing: -0.3,
                ),
              ),
              InkWell(
                onTap: () => setState(() => _isSearching = true),
                child: const Text(
                  'View all',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.resortEmerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Horizontal Featured Cards
          SizedBox(
            height: 270,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: resorts.length,
              itemBuilder: (context, index) {
                final resort = resorts[index];
                final units = _store.resortUnits[resort.id] ?? [];
                final startPrice = units.isNotEmpty ? units.first.pricePerNight : 120.0;
                final isFav = _favoriteResortIds.contains(resort.id);

                return Container(
                  width: 230,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.border(context)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/customer/resort/${resort.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                                child: SizedBox(
                                  height: 135,
                                  width: double.infinity,
                                  child: resort.imageUrls.isNotEmpty
                                      ? Image.network(
                                          resort.imageUrls.first,
                                          fit: BoxFit.cover,
                                          errorBuilder: (ctx, err, stack) => Container(
                                            color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                                            child: Icon(Icons.hotel_rounded, size: 36, color: AppTheme.textMuted(context)),
                                          ),
                                        )
                                      : Container(
                                          color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                                          child: Icon(Icons.hotel_rounded, size: 36, color: AppTheme.textMuted(context)),
                                        ),
                                ),
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.resortEmerald,
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '₹${startPrice.toStringAsFixed(0)}/night',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isFav) {
                                        _favoriteResortIds.remove(resort.id);
                                      } else {
                                        _favoriteResortIds.add(resort.id);
                                      }
                                    });
                                  },
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: (isDark ? const Color(0xFF1E2E28) : Colors.white).withValues(alpha: 0.9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      size: 17,
                                      color: isFav ? Colors.redAccent : AppTheme.textPrimary(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resort.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimary(context),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 16, color: AppTheme.resortGold),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${resort.rating}',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '(1.2k)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppTheme.textMuted(context),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textMuted(context)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${resort.city}, ${resort.state}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.textMuted(context),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 26),

          // Amenity Exploration Strip
          Text(
            'Explore Amenities',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary(context),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _amenityFilters.take(6).map((f) {
              final name = f['name'] as String;
              final isSelected = _selectedAmenities.contains(name);
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedAmenities.remove(name);
                    } else {
                      _selectedAmenities.add(name);
                    }
                    _isSearching = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.resortEmerald : AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? Colors.transparent : AppTheme.border(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        f['icon'] as IconData,
                        size: 15,
                        color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SCREEN 2: SEARCH RESULTS
  // ==========================================
  Widget _buildSearchResultsView(List<Resort> resorts) {
    final isDark = AppTheme.isDark(context);

    return Column(
      children: [
        // Top Navigation & Location Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppTheme.textPrimary(context)),
                  onPressed: () => setState(() => _isSearching = false),
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: InkWell(
                  onTap: _openLocationPicker,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _selectedCity == 'All Locations' ? 'All Destinations' : _selectedCity,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.textMuted(context)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          InkWell(
                            onTap: _openGuestPicker,
                            child: Text(
                              '$_adultsCount guest${_adultsCount > 1 ? 's' : ''}${_childrenCount > 0 ? ', $_childrenCount child' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            ' • ',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted(context),
                            ),
                          ),
                          InkWell(
                            onTap: _selectDateRange,
                            child: Text(
                              _dateRangeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.cardBg(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.border(context)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.map_outlined, size: 20, color: AppTheme.textPrimary(context)),
                  onPressed: _openLocationPicker,
                ),
              ),
            ],
          ),
        ),

        // Horizontal Filter & Amenities Pills Bar
        Container(
          height: 44,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _openFilterDialog,
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.border(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune_rounded, size: 16, color: AppTheme.textPrimary(context)),
                      const SizedBox(width: 6),
                      Text('Filter', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
                    ],
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sorted by: Top recommended for you'), behavior: SnackBarBehavior.floating),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppTheme.border(context)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sort_rounded, size: 16, color: AppTheme.textPrimary(context)),
                      const SizedBox(width: 6),
                      Text('Sort', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context))),
                    ],
                  ),
                ),
              ),
              ..._amenityFilters.map((f) {
                final name = f['name'] as String;
                final isSelected = _selectedAmenities.contains(name);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedAmenities.remove(name);
                        } else {
                          _selectedAmenities.add(name);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.resortEmerald : AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected ? Colors.transparent : AppTheme.border(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            f['icon'] as IconData,
                            size: 15,
                            color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppTheme.textPrimary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        // Result Count Summary
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${resorts.length} properties found',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted(context),
                ),
              ),
              if (_selectedAmenities.isNotEmpty || _selectedCity != 'All Locations')
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedAmenities.clear();
                      _selectedCity = 'All Locations';
                    });
                  },
                  child: const Text(
                    'Clear filters',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.resortEmerald,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Results Card List
        Expanded(
          child: resorts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 52, color: AppTheme.textMuted(context)),
                      const SizedBox(height: 14),
                      Text(
                        'No properties found matching filters',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedCity = 'All Locations';
                            _selectedAmenities.clear();
                          });
                        },
                        child: const Text('Reset All Filters'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  itemCount: resorts.length,
                  itemBuilder: (context, index) {
                    final resort = resorts[index];
                    final units = _store.resortUnits[resort.id] ?? [];
                    final startPrice = units.isNotEmpty ? units.first.pricePerNight : 120.0;
                    final isFav = _favoriteResortIds.contains(resort.id);
                    final scoreText = resort.rating >= 4.8 ? 'Superb' : (resort.rating >= 4.5 ? 'Fabulous' : 'Very Good');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg(context),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: AppTheme.border(context)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: SizedBox(
                                    height: 180,
                                    width: double.infinity,
                                    child: resort.imageUrls.isNotEmpty
                                        ? Image.network(
                                            resort.imageUrls.first,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) => Container(
                                              color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                                              child: Icon(Icons.hotel_rounded, size: 48, color: AppTheme.textMuted(context)),
                                            ),
                                          )
                                        : Container(
                                            color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                                            child: Icon(Icons.hotel_rounded, size: 48, color: AppTheme.textMuted(context)),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.resortEmerald,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.18),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      '₹${startPrice.toStringAsFixed(0)}/night',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (isFav) {
                                          _favoriteResortIds.remove(resort.id);
                                        } else {
                                          _favoriteResortIds.add(resort.id);
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: (isDark ? const Color(0xFF1E2E28) : Colors.white).withValues(alpha: 0.92),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                        size: 19,
                                        color: isFav ? Colors.redAccent : AppTheme.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  bottom: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '1/${resort.imageUrls.length > 1 ? resort.imageUrls.length : 12}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    resort.name,
                                    style: TextStyle(
                                      fontSize: 17.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimary(context),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 18, color: AppTheme.resortGold),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${resort.rating}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary(context),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '($scoreText)',
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
                            const SizedBox(height: 6),

                            InkWell(
                              onTap: () => _openGoogleMaps(resort),
                              borderRadius: BorderRadius.circular(4),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, size: 16, color: AppTheme.resortEmerald),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${resort.city}, ${resort.state} • 2.5 km from center',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: AppTheme.textMuted(context),
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF13382B) : AppTheme.resortSoftGreen,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Free cancellation available',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF6EE7B7) : AppTheme.resortDarkGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E2E28) : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Breakfast included',
                                    style: TextStyle(
                                      color: AppTheme.textPrimary(context),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                                ),
                                onPressed: () => context.go('/customer/resort/${resort.id}'),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('View Rooms', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                    SizedBox(width: 6),
                                    Icon(Icons.arrow_forward_rounded, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ==========================================
  // MOBILE ACCOUNT VIEW
  // ==========================================
  Widget _buildMobileAccountView() {
    final user = _store.currentUser;
    final isDark = AppTheme.isDark(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardBg(context),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.border(context)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                    child: Text(
                      user != null && user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'G',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user != null ? user.fullName : 'Guest Traveler',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary(context)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user != null ? user.email : 'Sign in to sync your bookings',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted(context)),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E2E28) : AppTheme.resortMintBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            user != null ? 'Role: ${user.role.displayName}' : 'Not Logged In',
                            style: TextStyle(fontSize: 11, color: isDark ? AppTheme.resortEmerald : AppTheme.resortDarkText, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          if (user != null) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Sign Out', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
                onPressed: () {
                  _store.logout();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out successfully.')),
                  );
                  context.go('/login');
                },
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login_rounded, size: 20),
                label: const Text('Sign In to ResortHub', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppTheme.resortEmerald : AppTheme.resortBlack,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
                onPressed: () => context.go('/login'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/resort.dart';
import '../../core/services/mock_data_store.dart';
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

  String _searchQuery = '';
  String _selectedCategory = 'Stays';
  String _selectedCity = 'All Locations'; // Dynamic initial city
  int _currentNavIndex = 0;

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
    end: DateTime.now().add(const Duration(days: 1)),
  );
  int _adultsCount = 2;
  int _childrenCount = 0;
  int _roomsCount = 1;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Stays', 'icon': Icons.bed},
    {'name': 'Beach Resorts', 'icon': Icons.beach_access},
    {'name': 'Hill Stations', 'icon': Icons.terrain},
    {'name': 'Eco Lodges', 'icon': Icons.eco},
    {'name': '5-Star Luxury', 'icon': Icons.star},
  ];

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final dayName = days[dt.weekday % 7];
    final monthName = months[dt.month - 1];
    return '$dayName ${dt.day} $monthName';
  }

  String get _dateRangeText {
    return '${_formatDate(_dateRange.start)} — ${_formatDate(_dateRange.end)}';
  }

  String get _guestSummaryText {
    final guests = '$_adultsCount adult${_adultsCount > 1 ? 's' : ''}${_childrenCount > 0 ? ', $_childrenCount child${_childrenCount > 1 ? 'ren' : ''}' : ''}';
    final rooms = '$_roomsCount room${_roomsCount > 1 ? 's' : ''}';
    return '$guests • $rooms';
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF003580),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
            ),
          ),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                      const Text(
                        'Select Rooms & Guests',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003580)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  
                  // Rooms Row
                  _buildCounterRow(
                    title: 'Rooms',
                    subtitle: 'Number of rooms reserved',
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

                  // Adults Row
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

                  // Children Row
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
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF006CE4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Apply Selection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: onDecrement,
              icon: Icon(Icons.remove_circle_outline, color: onDecrement != null ? const Color(0xFF006CE4) : Colors.grey.shade400),
            ),
            Text(
              '$value',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: onIncrement,
              icon: Icon(Icons.add_circle_outline, color: onIncrement != null ? const Color(0xFF006CE4) : Colors.grey.shade400),
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
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
                  const Text('Select Destination City', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF003580))),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.my_location, color: Color(0xFF006CE4)),
                title: const Text('Detect Current Location', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF006CE4))),
                subtitle: const Text('Auto-detect nearest resort destination via GPS', style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                tileColor: Colors.blue.shade50,
                onTap: () {
                  _detectUserLocationCity();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('📍 Location detected: $_selectedCity (Nearest resort area)'),
                      backgroundColor: const Color(0xFF003580),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cities.length,
                  itemBuilder: (context, index) {
                    final city = cities[index];
                    final isSelected = _selectedCity == city;

                    return ListTile(
                      leading: Icon(
                        city == 'All Locations' ? Icons.map : Icons.location_city,
                        color: isSelected ? const Color(0xFF006CE4) : Colors.grey,
                      ),
                      title: Text(
                        city,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF006CE4) : const Color(0xFF1A1A1A),
                        ),
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF006CE4)) : null,
                      onTap: () {
                        setState(() => _selectedCity = city);
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

  @override
  Widget build(BuildContext context) {
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

      bool matchesCategory = true;
      if (_selectedCategory == 'Beach Resorts') {
        matchesCategory = r.city.toLowerCase().contains('goa') || r.description.toLowerCase().contains('beach');
      } else if (_selectedCategory == 'Hill Stations') {
        matchesCategory = r.city.toLowerCase().contains('munnar') || r.city.toLowerCase().contains('shimla') || r.description.toLowerCase().contains('mountain');
      } else if (_selectedCategory == 'Eco Lodges') {
        matchesCategory = r.city.toLowerCase().contains('kumarakom') || r.description.toLowerCase().contains('eco');
      } else if (_selectedCategory == '5-Star Luxury') {
        matchesCategory = r.subscriptionTier == SubscriptionTier.premium || r.subscriptionTier == SubscriptionTier.superTier;
      }

      return matchesCity && matchesSearch && matchesCategory;
    }).toList();

    final sortedResorts = _locationService.sortResorts(
      resorts: rawResorts,
      userLocation: _locationService.defaultUserPosition,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003580),
        foregroundColor: Colors.white,
        elevation: 0,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text(
                'ResortHub',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.5, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEBB02), borderRadius: BorderRadius.circular(4)),
                child: const Text('INDIA', style: TextStyle(color: Color(0xFF003580), fontWeight: FontWeight.bold, fontSize: 9)),
              ),
            ],
          ),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(border: Border.all(color: Colors.white38), borderRadius: BorderRadius.circular(4)),
            child: const Text('INR ₹', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFEBB02)),
            tooltip: 'Logout',
            onPressed: () {
              MockDataStore.instance.logout();
              context.go('/login');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(sortedResorts),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        selectedItemColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFFEBB02) : const Color(0xFF003580),
        unselectedItemColor: Colors.grey.shade500,
        backgroundColor: Theme.of(context).cardColor,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentNavIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Stays'),
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number_outlined), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
      floatingActionButton: const AIAssistantFAB(),
    );
  }

  Widget _buildBody(List<Resort> sortedResorts) {
    if (_currentNavIndex == 1) {
      return const MyBookingsPage();
    }
    if (_currentNavIndex == 2) {
      return _buildMobileAccountView();
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Category Tabs Header
            Container(
              color: const Color(0xFF003580),
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat['name'];

                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = cat['name'] as String),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF00224F) : Colors.transparent,
                          border: isSelected ? Border.all(color: Colors.white, width: 1.5) : null,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(cat['icon'] as IconData, color: Colors.white, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              cat['name'] as String,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Signature Search Form Card
            Container(
              color: const Color(0xFF003580),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFFEBB02),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
                ),
                padding: const EdgeInsets.all(4),
                child: Column(
                  children: [
                    // City / Destination Row
                    InkWell(
                      onTap: _openLocationPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          children: [
                            const Icon(Icons.bed, color: Color(0xFF003580), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Where are you going?', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(_selectedCity, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A))),
                                ],
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Date & Guest Info Row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _selectDateRange,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                children: [
                                  const Icon(Icons.calendar_today, color: Color(0xFF003580), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _dateRangeText,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: InkWell(
                            onTap: _openGuestPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                              child: Row(
                                children: [
                                  const Icon(Icons.person, color: Color(0xFF003580), size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _guestSummaryText,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Search Button
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006CE4),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: () {
                          setState(() {});
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Showing resorts in $_selectedCity'),
                              backgroundColor: const Color(0xFF003580),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('Search', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Filter Bar / Results Counter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${sortedResorts.length} properties found in $_selectedCity',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_selectedCity != 'All Locations')
                    InkWell(
                      onTap: () => setState(() => _selectedCity = 'All Locations'),
                      child: const Text('Clear Filter', style: TextStyle(color: Color(0xFF006CE4), fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                ],
              ),
            ),

            // Property Cards List
            sortedResorts.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(36),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.search_off, size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text('No resorts found in $_selectedCity right now.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF006CE4)),
                            onPressed: () => setState(() => _selectedCity = 'All Locations'),
                            child: const Text('View All Properties'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: sortedResorts.length,
                    itemBuilder: (context, index) {
                      final resort = sortedResorts[index];
                      final units = _store.resortUnits[resort.id] ?? [];
                      final startPrice = units.isNotEmpty ? units.first.pricePerNight : 100.0;
                      final origPrice = startPrice * 1.25;

                      final scoreText = resort.rating >= 4.8
                          ? 'Superb'
                          : (resort.rating >= 4.5 ? 'Fabulous' : 'Very Good');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: InkWell(
                          onTap: () => context.go('/customer/resort/${resort.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Main Thumbnail Image
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        width: 100,
                                        height: 100,
                                        child: resort.imageUrls.isNotEmpty
                                            ? Image.network(
                                                resort.imageUrls.first,
                                                fit: BoxFit.cover,
                                                errorBuilder: (ctx, err, stack) => Container(color: Colors.grey.shade300, child: const Icon(Icons.hotel)),
                                              )
                                            : Container(color: Colors.grey.shade300, child: const Icon(Icons.hotel)),
                                      ),
                                    ),
                                    const SizedBox(width: 10),

                                    // Content Details
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  resort.name,
                                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF003580)),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF003580),
                                                  borderRadius: BorderRadius.all(Radius.circular(4)),
                                                ),
                                                child: Text(
                                                  '${resort.rating}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            scoreText,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF003580)),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.location_on, size: 12, color: Color(0xFF006CE4)),
                                              const SizedBox(width: 2),
                                              Expanded(
                                                child: Text(
                                                  '${resort.city}, ${resort.state}',
                                                  style: const TextStyle(color: Color(0xFF006CE4), fontSize: 11, fontWeight: FontWeight.w600),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                                            child: const Text('✓ Free cancellation', style: TextStyle(color: Color(0xFF008009), fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),

                                // Price & Availability CTA Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('₹${origPrice.toStringAsFixed(0)}', style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 11)),
                                          Text('₹${startPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1A1A))),
                                          Text('+ ₹${(startPrice * 0.12).toStringAsFixed(0)} taxes', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF006CE4),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      onPressed: () => context.go('/customer/resort/${resort.id}'),
                                      child: const Text('See availability', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      );
  }

  Widget _buildMobileAccountView() {
    final user = _store.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Card Header
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: const Color(0xFF003580),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: const Color(0xFFFEBB02),
                    child: Text(
                      user != null && user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'G',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF003580)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user != null ? user.fullName : 'Guest Traveler',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user != null ? user.email : 'Sign in to sync your bookings',
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            user != null ? 'Role: ${user.role.displayName}' : 'Not Logged In',
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          const Text('Account Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF003580))),
          const SizedBox(height: 12),

          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined, color: Color(0xFF003580)),
                  title: const Text('My Resort Passes & Bookings', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => _currentNavIndex = 1),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_outlined, color: Color(0xFF003580)),
                  title: const Text('Create New Account', style: TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/register'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.login, color: Color(0xFF003580)),
                  title: Text(user != null ? 'Switch Account / Sign In' : 'Sign In to ResortHub', style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/login'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

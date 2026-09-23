import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/resort.dart';
import '../models/subscription.dart';
import '../models/unit.dart';
import '../models/reservation.dart';
import '../models/payment.dart';
import '../models/staff.dart';
import '../models/food.dart';
import '../models/expense.dart';
import '../models/report.dart';
import '../models/salary_disbursement.dart';

class MockDataStore {
  static final MockDataStore instance = MockDataStore._internal();

  MockDataStore._internal() {
    _initMockData();
    _loadPersistedData();
  }

  // Pre-configured User Profiles for all 5 roles
  final Map<String, UserProfile> profiles = {};
  
  // User Passwords store
  final Map<String, String> _userPasswords = {};

  // Deleted and Custom Resort IDs for local persistence across app restarts
  final Set<String> _deletedResortIds = {};
  final Set<String> _customResortIds = {};

  // Resorts across all 4 subscription tiers
  final Map<String, Resort> resorts = {};

  // Subscriptions & Plans
  final List<SubscriptionPlan> subscriptionPlans = [];
  final Map<String, ResortSubscription> resortSubscriptions = {};
  final List<SubscriptionPayment> subscriptionPayments = [];

  // Units & Rate Rules
  final Map<String, List<ResortUnit>> resortUnits = {};
  final Map<String, List<RateRule>> resortRateRules = {};

  // Reservations & Booking Payments
  final List<Reservation> reservations = [];
  final List<BookingPayment> bookingPayments = [];

  // Staff & Operational Data
  final Map<String, List<StaffMember>> resortStaff = {};
  final Map<String, List<StaffTask>> resortTasks = {};

  // Food & Services
  final Map<String, List<FoodItem>> resortFoodItems = {};
  final Map<String, List<FoodOrder>> resortFoodOrders = {};

  // Accounting & Expenses
  final Map<String, List<ResortExpense>> resortExpenses = {};
  final Map<String, List<LedgerSettlement>> resortLedgerSettlements = {};

  // Salary Disbursements
  final Map<String, List<InchargeSalaryPayment>> inchargeSalaryPayments = {};
  final Map<String, List<StaffSalaryPayment>> staffSalaryPayments = {};

  // Tier Change Requests (Admin <-> Super Admin)
  final List<TierChangeRequest> tierChangeRequests = [];

  // Staff Salary Funding Requests (Incharge -> Admin)
  final List<StaffSalaryFundRequest> staffSalaryFundRequests = [];

  // Currently logged in user profile (for stateful demo mode)
  UserProfile? currentUser;

  // Selected resort context for Super Admin inspection (BR-09)
  String? superAdminSelectedResortId;

  void _initMockData() {
    // 1. Subscription Plans
    subscriptionPlans.addAll([
      const SubscriptionPlan(
        id: 'plan-premium',
        tier: SubscriptionTier.premium,
        name: 'Premium Tier Plan',
        priceMonthly: 299.00,
        features: ['Top Priority Discovery', 'Unlimited Analytics', 'Full Financial Auditing', '24/7 Priority Support'],
      ),
      const SubscriptionPlan(
        id: 'plan-super',
        tier: SubscriptionTier.superTier,
        name: 'Super Tier Plan',
        priceMonthly: 149.00,
        features: ['Elevated Discovery', 'Advanced Staff Ops', 'Standard Reports', 'Email Support'],
      ),
      const SubscriptionPlan(
        id: 'plan-basic',
        tier: SubscriptionTier.basic,
        name: 'Basic Tier Plan',
        priceMonthly: 49.00,
        features: ['Standard Discovery', 'Basic Booking', 'Core Reporting'],
      ),
      const SubscriptionPlan(
        id: 'plan-free',
        tier: SubscriptionTier.free,
        name: 'Free Tier Plan',
        priceMonthly: 0.00,
        features: ['Basic Listing', 'Manual Confirmation Only'],
      ),
    ]);

    // 2. Resorts
    final grandPalms = Resort(
      id: 'resort-grand-palms',
      name: 'Grand Palms Beach Resort',
      slug: 'grand-palms',
      description: 'Ultra-luxury 5-star beachfront paradise featuring private infinity pools, wellness spa, and gourmet dining.',
      address: '100 Oceanfront Boulevard, Calangute',
      city: 'Calangute',
      state: 'Goa',
      country: 'India',
      latitude: 15.5497,
      longitude: 73.7536,
      contactEmail: 'contact@grandpalms.com',
      contactPhone: '+91 98765 43210',
      subscriptionTier: SubscriptionTier.premium,
      status: 'active',
      imageUrls: const [
        'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
        'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800',
      ],
      amenities: const ['Private Beach', 'Swimming Pool', 'Luxury Spa', 'Gourmet Restaurant', 'Free Wi-Fi', 'Airport Shuttle', 'Free Parking', 'Air Conditioning'],
      rating: 4.9,
    );

    final highlandMist = Resort(
      id: 'resort-highland-mist',
      name: 'Highland Mist Mountain Resort',
      slug: 'highland-mist',
      description: 'Serene hillside retreat nestled in lush tea plantations with scenic mountain panoramas and bonfire nights.',
      address: '45 Estate Road, Munnar',
      city: 'Munnar',
      state: 'Kerala',
      country: 'India',
      latitude: 10.0889,
      longitude: 77.0595,
      contactEmail: 'info@highlandmist.com',
      contactPhone: '+91 98765 43211',
      subscriptionTier: SubscriptionTier.superTier,
      status: 'active',
      imageUrls: const [
        'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800',
      ],
      amenities: const ['Mountain View', 'Swimming Pool', 'Tea Garden Walks', 'Fireplace Lounge', 'Restaurant', 'Free Wi-Fi', 'Free Parking'],
      rating: 4.7,
    );

    final lakesideEco = Resort(
      id: 'resort-lakeside-eco',
      name: 'Lakeside Eco Lodge',
      slug: 'lakeside-eco',
      description: 'Tranquil lakeside eco-resort with wooden cottages, kayaking, organic dining, and bird watching.',
      address: '12 Vembanad Lake Trail, Kumarakom',
      city: 'Kumarakom',
      state: 'Kerala',
      country: 'India',
      latitude: 9.6175,
      longitude: 76.4301,
      contactEmail: 'hello@lakesideeco.com',
      contactPhone: '+91 98765 43212',
      subscriptionTier: SubscriptionTier.basic,
      status: 'active',
      imageUrls: const [
        'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800',
      ],
      amenities: const ['Lake View', 'Swimming Pool', 'Kayaking', 'Organic Dining', 'Garden', 'Free Wi-Fi', 'Free Parking'],
      rating: 4.3,
    );

    final pineValley = Resort(
      id: 'resort-pine-valley',
      name: 'Pine Valley Budget Cottages',
      slug: 'pine-valley',
      description: 'Cozy budget-friendly wooden chalets surrounded by pine forests with essential amenities.',
      address: '88 Pine Woods Way, Manali',
      city: 'Manali',
      state: 'Himachal Pradesh',
      country: 'India',
      latitude: 32.2432,
      longitude: 77.1892,
      contactEmail: 'stay@pinevalley.com',
      contactPhone: '+91 98765 43213',
      subscriptionTier: SubscriptionTier.free,
      status: 'active',
      imageUrls: const [
        'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      ],
      amenities: const ['Forest View', 'Hot Water', 'Free Parking', 'Bonfire', 'Free Wi-Fi', 'Restaurant'],
      rating: 4.0,
    );

    resorts[grandPalms.id] = grandPalms;
    resorts[highlandMist.id] = highlandMist;
    resorts[lakesideEco.id] = lakesideEco;
    resorts[pineValley.id] = pineValley;

    // --- 15 Additional Resorts Setup ---
    final List<Map<String, dynamic>> extraResortsList = [
      {
        'id': 'resort-taj-falaknuma',
        'name': 'Taj Falaknuma Palace Resort',
        'city': 'Hyderabad',
        'state': 'Telangana',
        'tier': SubscriptionTier.premium,
        'rating': 4.9,
        'email': 'falaknuma@tajresorts.com',
        'desc': '5-star royal Nizam palace resort 2000 feet above Hyderabad with heritage gardens.',
        'lat': 17.3316,
        'lng': 78.4674,
        'adminName': 'Mirza Baig (Resort Admin)',
        'adminEmail': 'admin.hyderabad1@resorthub.com',
        'inchargeName': 'Syed Ali (Ops Incharge)',
        'inchargeEmail': 'incharge.hyderabad1@resorthub.com',
        'unitName': 'Nizam Royal Palace Suite',
        'unitPrice': 680.00,
        'planId': 'plan-premium',
        'img': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
      {
        'id': 'resort-golkonda-hyderabad',
        'name': 'Golkonda Resort & Spa',
        'city': 'Hyderabad',
        'state': 'Telangana',
        'tier': SubscriptionTier.superTier,
        'rating': 4.7,
        'email': 'stay@golkondaresort.com',
        'desc': 'Serene 5-star villa resort near Osman Sagar Lake, Gandipet with luxury spa pools.',
        'lat': 17.3871,
        'lng': 78.3182,
        'adminName': 'Rajeshwar Reddy (Unassigned Admin)',
        'adminEmail': 'admin.hyderabad2@resorthub.com',
        'inchargeName': 'Venkatesh Rao (Ops Incharge)',
        'inchargeEmail': 'incharge.hyderabad2@resorthub.com',
        'unitName': 'Duplex Garden Villa',
        'unitPrice': 320.00,
        'planId': 'plan-super',
        'img': 'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800',
      },
      {
        'id': 'resort-taj-lake',
        'name': 'Taj Lake Palace Heritage',
        'city': 'Udaipur',
        'state': 'Rajasthan',
        'tier': SubscriptionTier.premium,
        'rating': 4.9,
        'email': 'lake.palace@tajresorts.com',
        'desc': 'Iconic floating marble palace resort situated in the middle of Lake Pichola.',
        'lat': 24.5764,
        'lng': 73.6835,
        'adminName': 'Karan Singh (Unassigned Admin)',
        'adminEmail': 'admin.udaipur@resorthub.com',
        'inchargeName': 'Bhawani Singh (Ops Incharge)',
        'inchargeEmail': 'incharge.udaipur@resorthub.com',
        'unitName': 'Grand Royal Lake Suite',
        'unitPrice': 620.00,
        'planId': 'plan-premium',
        'img': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
      {
        'id': 'resort-leela-kovalam',
        'name': 'The Leela Palace Ocean Resort',
        'city': 'Kovalam',
        'state': 'Kerala',
        'tier': SubscriptionTier.premium,
        'rating': 4.8,
        'email': 'kovalam@theleela.com',
        'desc': 'Cliffside 5-star oceanfront resort offering panoramic views of the Arabian Sea.',
        'lat': 8.4004,
        'lng': 76.9787,
        'adminName': 'Madhavan Nair (Unassigned Admin)',
        'adminEmail': 'admin.kovalam@resorthub.com',
        'inchargeName': 'Suresh Kurup (Ops Incharge)',
        'inchargeEmail': 'incharge.kovalam@resorthub.com',
        'unitName': 'Ocean View Pavilion',
        'unitPrice': 480.00,
        'planId': 'plan-premium',
        'img': 'https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800',
      },
      {
        'id': 'resort-wildflower-shimla',
        'name': 'Wildflower Hall Mountain Sanctuary',
        'city': 'Shimla',
        'state': 'Himachal Pradesh',
        'tier': SubscriptionTier.premium,
        'rating': 4.9,
        'email': 'shimla@oberoi.com',
        'desc': 'Luxury pine forest mountain sanctuary with heated outdoor whirlpool and snow views.',
        'lat': 31.1048,
        'lng': 77.1734,
        'adminName': 'Rohit Thakur (Unassigned Admin)',
        'adminEmail': 'admin.shimla@resorthub.com',
        'inchargeName': 'Deepak Sharma (Ops Incharge)',
        'inchargeEmail': 'incharge.shimla@resorthub.com',
        'unitName': 'Lord Kitchener Suite',
        'unitPrice': 550.00,
        'planId': 'plan-premium',
        'img': 'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800',
      },
      {
        'id': 'resort-evolve-kabini',
        'name': 'Evolve Back Wilderness Lodge',
        'city': 'Kabini',
        'state': 'Karnataka',
        'tier': SubscriptionTier.premium,
        'rating': 4.9,
        'email': 'kabini@evolveback.com',
        'desc': 'Tribal-inspired eco luxury jungle resort nestled on the banks of Kabini river.',
        'lat': 11.9261,
        'lng': 76.3532,
        'adminName': 'Ganesh Gowda (Unassigned Admin)',
        'adminEmail': 'admin.kabini@resorthub.com',
        'inchargeName': 'Subbaiah Poovaiah (Ops Incharge)',
        'inchargeEmail': 'incharge.kabini@resorthub.com',
        'unitName': 'Jacuzzi Hut Villa',
        'unitPrice': 410.00,
        'planId': 'plan-premium',
        'img': 'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800',
      },
      {
        'id': 'resort-alila-diwa',
        'name': 'Alila Diwa Luxury Retreat',
        'city': 'Majorda',
        'state': 'Goa',
        'tier': SubscriptionTier.superTier,
        'rating': 4.7,
        'email': 'diwa@alilahotels.com',
        'desc': 'Lush paddy field luxury retreat in South Goa featuring infinity pool and spa.',
        'lat': 15.3168,
        'lng': 73.9082,
        'adminName': 'Neelam Fernandes (Unassigned Admin)',
        'adminEmail': 'admin.majorda@resorthub.com',
        'inchargeName': 'Caetano Dsouza (Ops Incharge)',
        'inchargeEmail': 'incharge.majorda@resorthub.com',
        'unitName': 'Diwa Club Room',
        'unitPrice': 290.00,
        'planId': 'plan-super',
        'img': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
      {
        'id': 'resort-machan-lonavala',
        'name': 'The Machan Treehouse Resort',
        'city': 'Lonavala',
        'state': 'Maharashtra',
        'tier': SubscriptionTier.superTier,
        'rating': 4.6,
        'email': 'stay@themachan.com',
        'desc': 'Exclusive eco-resort with luxury treehouses rising 30-45 feet above canopy level.',
        'lat': 18.7557,
        'lng': 73.4091,
        'adminName': 'Sameer Deshmukh (Unassigned Admin)',
        'adminEmail': 'admin.lonavala@resorthub.com',
        'inchargeName': 'Pravin Kadam (Ops Incharge)',
        'inchargeEmail': 'incharge.lonavala@resorthub.com',
        'unitName': 'Canopy Treehouse',
        'unitPrice': 240.00,
        'planId': 'plan-super',
        'img': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
      {
        'id': 'resort-kumarakom-lake',
        'name': 'Kumarakom Lake Resort',
        'city': 'Kumarakom',
        'state': 'Kerala',
        'tier': SubscriptionTier.superTier,
        'rating': 4.8,
        'email': 'stay@kumarakomlakeresort.in',
        'desc': 'Traditional Heritage Villas with private pool and meandering pool villas on Lake Vembanad.',
        'lat': 9.6175,
        'lng': 76.4301,
        'adminName': 'Venugopal Menon (Unassigned Admin)',
        'adminEmail': 'admin.kumarakom@resorthub.com',
        'inchargeName': 'Ashok Kumar (Ops Incharge)',
        'inchargeEmail': 'incharge.kumarakom@resorthub.com',
        'unitName': 'Meandering Pool Villa',
        'unitPrice': 310.00,
        'planId': 'plan-super',
        'img': 'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800',
      },
      {
        'id': 'resort-aravalli-ranthambore',
        'name': 'Aravalli Hills Safari Lodge',
        'city': 'Ranthambore',
        'state': 'Rajasthan',
        'tier': SubscriptionTier.superTier,
        'rating': 4.5,
        'email': 'safari@aravalli.com',
        'desc': 'Wildlife safari retreat bordering tiger reserve forest with luxury glamping tents.',
        'lat': 26.0173,
        'lng': 76.5026,
        'adminName': 'Raghuvendra Rathore (Unassigned Admin)',
        'adminEmail': 'admin.ranthambore@resorthub.com',
        'inchargeName': 'Mahipal Singh (Ops Incharge)',
        'inchargeEmail': 'incharge.ranthambore@resorthub.com',
        'unitName': 'Royal Glamping Safari Tent',
        'unitPrice': 210.00,
        'planId': 'plan-super',
        'img': 'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800',
      },
      {
        'id': 'resort-cedar-mussoorie',
        'name': 'Cedar Heights Mountain Chalet',
        'city': 'Mussoorie',
        'state': 'Uttarakhand',
        'tier': SubscriptionTier.basic,
        'rating': 4.4,
        'email': 'stay@cedarmussoorie.com',
        'desc': 'Cozy cedarwood hillside chalet overlooking Doon valley with mountain views.',
        'lat': 30.4598,
        'lng': 78.0644,
        'adminName': 'Vikram Negi (Unassigned Admin)',
        'adminEmail': 'admin.mussoorie@resorthub.com',
        'inchargeName': 'Sunil Rawat (Ops Incharge)',
        'inchargeEmail': 'incharge.mussoorie@resorthub.com',
        'unitName': 'Doon Valley Chalet',
        'unitPrice': 135.00,
        'planId': 'plan-basic',
        'img': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
      {
        'id': 'resort-backwater-alleppey',
        'name': 'Backwater Palms Cottage',
        'city': 'Alleppey',
        'state': 'Kerala',
        'tier': SubscriptionTier.basic,
        'rating': 4.3,
        'email': 'info@alleppeypalms.com',
        'desc': 'Charming backwater palm cottage with traditional Kerala canoe trips.',
        'lat': 9.4981,
        'lng': 76.3388,
        'adminName': 'Jacob Thomas (Unassigned Admin)',
        'adminEmail': 'admin.alleppey@resorthub.com',
        'inchargeName': 'Sebastian Joseph (Ops Incharge)',
        'inchargeEmail': 'incharge.alleppey@resorthub.com',
        'unitName': 'Backwater Palm Room',
        'unitPrice': 110.00,
        'planId': 'plan-basic',
        'img': 'https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800',
      },
      {
        'id': 'resort-valley-ooty',
        'name': 'Valley View Eco Cottages',
        'city': 'Ooty',
        'state': 'Tamil Nadu',
        'tier': SubscriptionTier.basic,
        'rating': 4.2,
        'email': 'booking@valleyooty.com',
        'desc': 'Tranquil cottages overlooking Nilgiri hills with organic eucalyptus garden.',
        'lat': 11.4102,
        'lng': 76.6950,
        'adminName': 'Karthik Raja (Unassigned Admin)',
        'adminEmail': 'admin.ooty@resorthub.com',
        'inchargeName': 'Murugan Swamy (Ops Incharge)',
        'inchargeEmail': 'incharge.ooty@resorthub.com',
        'unitName': 'Nilgiri Hill Cottage',
        'unitPrice': 95.00,
        'planId': 'plan-basic',
        'img': 'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800',
      },
      {
        'id': 'resort-emerald-kodaikanal',
        'name': 'Emerald Pines Resort',
        'city': 'Kodaikanal',
        'state': 'Tamil Nadu',
        'tier': SubscriptionTier.basic,
        'rating': 4.3,
        'email': 'stay@emeraldkodai.com',
        'desc': 'Lakeside pine forest cottages with misty morning boat rides.',
        'lat': 10.2381,
        'lng': 77.4892,
        'adminName': 'Srinivasan Raman (Unassigned Admin)',
        'adminEmail': 'admin.kodaikanal@resorthub.com',
        'inchargeName': 'Gokul Nathan (Ops Incharge)',
        'inchargeEmail': 'incharge.kodaikanal@resorthub.com',
        'unitName': 'Emerald Forest Villa',
        'unitPrice': 125.00,
        'planId': 'plan-basic',
        'img': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
      {
        'id': 'resort-breeze-wayanad',
        'name': 'Valley Breeze Haven',
        'city': 'Wayanad',
        'state': 'Kerala',
        'tier': SubscriptionTier.free,
        'rating': 4.1,
        'email': 'breeze@wayanadhaven.com',
        'desc': 'Budget-friendly rainforest lodge surrounded by pepper and cardamom plantations.',
        'lat': 11.6854,
        'lng': 76.1320,
        'adminName': 'Mathew Varghese (Unassigned Admin)',
        'adminEmail': 'admin.wayanad@resorthub.com',
        'inchargeName': 'Jijo George (Ops Incharge)',
        'inchargeEmail': 'incharge.wayanad@resorthub.com',
        'unitName': 'Cardamom Plantation Room',
        'unitPrice': 55.00,
        'planId': 'plan-free',
        'img': 'https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800',
      },
      {
        'id': 'resort-himalayan-rishikesh',
        'name': 'Himalayan River Chalet',
        'city': 'Rishikesh',
        'state': 'Uttarakhand',
        'tier': SubscriptionTier.free,
        'rating': 4.0,
        'email': 'river@himalayanrishikesh.com',
        'desc': 'Riverside budget wooden cottages with Ganges views and yoga deck.',
        'lat': 30.0869,
        'lng': 78.2676,
        'adminName': 'Amit Joshi (Unassigned Admin)',
        'adminEmail': 'admin.rishikesh@resorthub.com',
        'inchargeName': 'Sanjay Bhatt (Ops Incharge)',
        'inchargeEmail': 'incharge.rishikesh@resorthub.com',
        'unitName': 'Ganges View Cottage',
        'unitPrice': 50.00,
        'planId': 'plan-free',
        'img': 'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800',
      },
      {
        'id': 'resort-sunset-jaisalmer',
        'name': 'Sunset Dunes Camp & Resort',
        'city': 'Jaisalmer',
        'state': 'Rajasthan',
        'tier': SubscriptionTier.free,
        'rating': 4.2,
        'email': 'dunes@sunsetjaisalmer.com',
        'desc': 'Thar desert sand dune desert camp featuring folk dance performances and camel safaris.',
        'lat': 26.9157,
        'lng': 70.9083,
        'adminName': 'Hanuman Singh (Unassigned Admin)',
        'adminEmail': 'admin.jaisalmer@resorthub.com',
        'inchargeName': 'Jaswant Singh (Ops Incharge)',
        'inchargeEmail': 'incharge.jaisalmer@resorthub.com',
        'unitName': 'Desert Safari Tent',
        'unitPrice': 60.00,
        'planId': 'plan-free',
        'img': 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      },
    ];

    for (final item in extraResortsList) {
      final rId = item['id'] as String;
      final resortObj = Resort(
        id: rId,
        name: item['name'] as String,
        slug: rId.replaceAll('resort-', ''),
        description: item['desc'] as String,
        address: '100 Resort Way, ${item['city']}',
        city: item['city'] as String,
        state: item['state'] as String,
        country: 'India',
        latitude: item['lat'] as double,
        longitude: item['lng'] as double,
        contactEmail: item['email'] as String,
        contactPhone: '+91 98000 ${10000 + extraResortsList.indexOf(item)}',
        subscriptionTier: item['tier'] as SubscriptionTier,
        status: 'active',
        imageUrls: [item['img'] as String],
        amenities: (item['amenities'] as List<String>?) ??
            const [
              'Free Wi-Fi',
              'Swimming Pool',
              'Luxury Spa',
              'Restaurant',
              'Free Parking',
              'Air Conditioning',
            ],
        rating: item['rating'] as double,
      );
      resorts[rId] = resortObj;

      // Active Subscription
      resortSubscriptions[rId] = ResortSubscription(
        id: 'sub-$rId',
        resortId: rId,
        planId: item['planId'] as String,
        tier: item['tier'] as SubscriptionTier,
        status: SubscriptionStatus.active,
        currentPeriodStart: DateTime.now().subtract(const Duration(days: 10)),
        currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
        cancelAtPeriodEnd: false,
      );

      // ASSIGNED RESORT ADMIN USER ACCOUNT
      final adminUser = UserProfile(
        id: 'usr-admin-$rId',
        email: item['adminEmail'] as String,
        fullName: (item['adminName'] as String).replaceAll(' (Unassigned Admin)', ' (Resort Admin)'),
        role: AppRole.admin,
        resortId: rId, // ASSIGNED INITIAL STATE
        phone: '+91 98765 ${10000 + extraResortsList.indexOf(item)}',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      profiles[adminUser.email] = adminUser;

      // OPERATIONAL INCHARGE ACCOUNT (assigned to resort)
      final inchargeUser = UserProfile(
        id: 'usr-incharge-$rId',
        email: item['inchargeEmail'] as String,
        fullName: item['inchargeName'] as String,
        role: AppRole.incharge,
        resortId: rId,
        phone: '+91 98765 ${20000 + extraResortsList.indexOf(item)}',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      profiles[inchargeUser.email] = inchargeUser;

      // RESORT UNIT
      resortUnits[rId] = [
        ResortUnit(
          id: 'unit-$rId-1',
          resortId: rId,
          name: item['unitName'] as String,
          type: 'room',
          capacity: 2,
          pricePerNight: item['unitPrice'] as double,
          description: 'Comfortable guest unit with premium amenities and mountain/waterfront view.',
          status: 'available',
          amenities: const ['Air Conditioning', 'Free Wi-Fi', 'Ensuite Bath'],
          imageUrls: [item['img'] as String],
        )
      ];
    }

    // 3. User Profiles for all 5 roles
    final userSuperAdmin = UserProfile(
      id: 'usr-super-admin',
      email: 'owner@resorthub.com',
      fullName: 'Vikramaditya Roy (Co-owner)',
      role: AppRole.superAdmin,
      phone: '+91 99999 00000',
      createdAt: DateTime.now().subtract(const Duration(days: 365)),
    );

    final userResortAdmin = UserProfile(
      id: 'usr-resort-admin',
      email: 'admin@grandpalms.com',
      fullName: 'Ananya Sharma (Resort Admin)',
      role: AppRole.admin,
      resortId: grandPalms.id,
      phone: '+91 98765 11111',
      createdAt: DateTime.now().subtract(const Duration(days: 180)),
    );

    final userIncharge = UserProfile(
      id: 'usr-incharge',
      email: 'incharge@grandpalms.com',
      fullName: 'Rajesh Kumar (Ops Incharge)',
      role: AppRole.incharge,
      resortId: grandPalms.id,
      phone: '+91 98765 22222',
      createdAt: DateTime.now().subtract(const Duration(days: 120)),
    );

    final userAccountant = UserProfile(
      id: 'usr-accountant',
      email: 'accountant@grandpalms.com',
      fullName: 'Priya Nair (Lead Accountant)',
      role: AppRole.accountant,
      resortId: grandPalms.id,
      phone: '+91 98765 33333',
      createdAt: DateTime.now().subtract(const Duration(days: 90)),
    );

    final userCustomer = UserProfile(
      id: 'usr-customer',
      email: 'customer@example.com',
      fullName: 'Rahul Verma',
      role: AppRole.customer,
      phone: '+91 98765 44444',
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    );

    final adminHighlandMist = UserProfile(
      id: 'usr-admin-highland-mist',
      email: 'admin@highlandmist.com',
      fullName: 'Ramesh Nair (Resort Admin)',
      role: AppRole.admin,
      resortId: highlandMist.id,
      phone: '+91 98765 11112',
      createdAt: DateTime.now().subtract(const Duration(days: 150)),
    );

    final adminLakesideEco = UserProfile(
      id: 'usr-admin-lakeside-eco',
      email: 'admin@lakesideeco.com',
      fullName: 'Sunil Varghese (Resort Admin)',
      role: AppRole.admin,
      resortId: lakesideEco.id,
      phone: '+91 98765 11113',
      createdAt: DateTime.now().subtract(const Duration(days: 140)),
    );

    final adminPineValley = UserProfile(
      id: 'usr-admin-pine-valley',
      email: 'admin@pinevalley.com',
      fullName: 'Vijay Kumar (Resort Admin)',
      role: AppRole.admin,
      resortId: pineValley.id,
      phone: '+91 98765 11114',
      createdAt: DateTime.now().subtract(const Duration(days: 130)),
    );

    profiles[userSuperAdmin.email] = userSuperAdmin;
    profiles[userResortAdmin.email] = userResortAdmin;
    profiles[adminHighlandMist.email] = adminHighlandMist;
    profiles[adminLakesideEco.email] = adminLakesideEco;
    profiles[adminPineValley.email] = adminPineValley;
    profiles[userIncharge.email] = userIncharge;
    profiles[userAccountant.email] = userAccountant;
    profiles[userCustomer.email] = userCustomer;
    currentUser = userCustomer;

    // Dedicated Accountants for each resort
    final accPineValley = UserProfile(
      id: 'usr-acc-pinevalley',
      email: 'accountant@pinevalley.com',
      fullName: 'Anand Joshi (Pine Valley Accountant)',
      role: AppRole.accountant,
      resortId: pineValley.id,
      phone: '+91 98765 44411',
      createdAt: DateTime.now().subtract(const Duration(days: 80)),
    );
    final accHighlandMist = UserProfile(
      id: 'usr-acc-highlandmist',
      email: 'accountant@highlandmist.com',
      fullName: 'Meera Iyer (Highland Mist Accountant)',
      role: AppRole.accountant,
      resortId: highlandMist.id,
      phone: '+91 98765 44422',
      createdAt: DateTime.now().subtract(const Duration(days: 75)),
    );
    final accLakesideEco = UserProfile(
      id: 'usr-acc-lakesideeco',
      email: 'accountant@lakesideeco.com',
      fullName: 'Sanjay Rao (Lakeside Eco Accountant)',
      role: AppRole.accountant,
      resortId: lakesideEco.id,
      phone: '+91 98765 44433',
      createdAt: DateTime.now().subtract(const Duration(days: 70)),
    );
    profiles[accPineValley.email] = accPineValley;
    profiles[accHighlandMist.email] = accHighlandMist;
    profiles[accLakesideEco.email] = accLakesideEco;

    // Separate Master Platform Accountant for ResortHub (views all subscribed resorts in the app)
    final platformAccountant = UserProfile(
      id: 'usr-accountant-resorthub',
      email: 'accountant@resorthub.com',
      fullName: 'Vikram Mehta (Platform Chief Accountant)',
      role: AppRole.accountant,
      resortId: null, // Full platform-wide visibility across all subscribed resorts
      phone: '+91 98765 99000',
      createdAt: DateTime.now().subtract(const Duration(days: 100)),
    );
    profiles[platformAccountant.email] = platformAccountant;

    // Seed an initial staff salary funding request from incharge to admin for Grand Palms
    staffSalaryFundRequests.add(StaffSalaryFundRequest(
      id: 'req-fund-initial-gp',
      resortId: grandPalms.id,
      inchargeEmail: userIncharge.email,
      inchargeName: userIncharge.fullName,
      monthYear: 'September 2026',
      requestedAmount: 60000.0,
      staffCount: 4,
      notes: 'Monthly ground staff wages for 4 operational team members: Chef, Housekeeper, Security, Maintenance.',
      status: StaffFundRequestStatus.pending,
      createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    ));

    // 5 Additional Pre-configured Customer Accounts
    final customer1 = UserProfile(
      id: 'usr-cust-1',
      email: 'customer1@resorthub.com',
      fullName: 'Ananya Sharma',
      role: AppRole.customer,
      phone: '+91 98765 11111',
      createdAt: DateTime.now().subtract(const Duration(days: 20)),
    );
    final customer2 = UserProfile(
      id: 'usr-cust-2',
      email: 'customer2@resorthub.com',
      fullName: 'Vikram Malhotra',
      role: AppRole.customer,
      phone: '+91 98765 22222',
      createdAt: DateTime.now().subtract(const Duration(days: 18)),
    );
    final customer3 = UserProfile(
      id: 'usr-cust-3',
      email: 'customer3@resorthub.com',
      fullName: 'Priya Reddy',
      role: AppRole.customer,
      phone: '+91 98765 33333',
      createdAt: DateTime.now().subtract(const Duration(days: 15)),
    );
    final customer4 = UserProfile(
      id: 'usr-cust-4',
      email: 'customer4@resorthub.com',
      fullName: 'Rohan Gupta',
      role: AppRole.customer,
      phone: '+91 98765 44444',
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    );
    final customer5 = UserProfile(
      id: 'usr-cust-5',
      email: 'customer5@resorthub.com',
      fullName: 'Sneha Nair',
      role: AppRole.customer,
      phone: '+91 98765 55555',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    );

    profiles[customer1.email] = customer1;
    profiles[customer2.email] = customer2;
    profiles[customer3.email] = customer3;
    profiles[customer4.email] = customer4;
    profiles[customer5.email] = customer5;

    // No default session — user must log in

    // 4. Resort Subscriptions
    resortSubscriptions[grandPalms.id] = ResortSubscription(
      id: 'sub-gp',
      resortId: grandPalms.id,
      planId: 'plan-premium',
      tier: SubscriptionTier.premium,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now().subtract(const Duration(days: 15)),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 15)),
      cancelAtPeriodEnd: false,
    );

    resortSubscriptions[highlandMist.id] = ResortSubscription(
      id: 'sub-hm',
      resortId: highlandMist.id,
      planId: 'plan-super',
      tier: SubscriptionTier.superTier,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now().subtract(const Duration(days: 10)),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 20)),
      cancelAtPeriodEnd: false,
    );

    resortSubscriptions[lakesideEco.id] = ResortSubscription(
      id: 'sub-le',
      resortId: lakesideEco.id,
      planId: 'plan-basic',
      tier: SubscriptionTier.basic,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now().subtract(const Duration(days: 5)),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 25)),
      cancelAtPeriodEnd: false,
    );

    resortSubscriptions[pineValley.id] = ResortSubscription(
      id: 'sub-pv',
      resortId: pineValley.id,
      planId: 'plan-free',
      tier: SubscriptionTier.free,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now().subtract(const Duration(days: 60)),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 300)),
      cancelAtPeriodEnd: false,
    );

    // 5. Subscription Payments
    subscriptionPayments.add(
      SubscriptionPayment(
        id: 'sub-pay-1',
        subscriptionId: 'sub-gp',
        resortId: grandPalms.id,
        amount: 299.00,
        status: PaymentStatus.succeeded,
        transactionRef: 'SUB-TXN-99881',
        idempotencyKey: 'idemp-sub-1',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
    );

    subscriptionPayments.add(
      SubscriptionPayment(
        id: 'sub-pay-2',
        subscriptionId: 'sub-hm',
        resortId: highlandMist.id,
        amount: 149.00,
        status: PaymentStatus.succeeded,
        transactionRef: 'SUB-TXN-99882',
        idempotencyKey: 'idemp-sub-2',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    );

    // 6. Units
    resortUnits[grandPalms.id] = [
      const ResortUnit(
        id: 'unit-gp-101',
        resortId: 'resort-grand-palms',
        name: 'Ocean Villa 101',
        type: 'villa',
        capacity: 4,
        pricePerNight: 450.00,
        description: 'Luxury beachfront villa with private plunge pool and direct ocean balcony access.',
        status: 'available',
        amenities: ['King Bed', 'Private Pool', 'Ocean View', 'Mini Bar', 'Jacuzzi'],
        imageUrls: ['https://images.unsplash.com/photo-1582719508461-905c673771fd?w=800'],
      ),
      const ResortUnit(
        id: 'unit-gp-202',
        resortId: 'resort-grand-palms',
        name: 'Deluxe Garden Suite 202',
        type: 'suite',
        capacity: 2,
        pricePerNight: 250.00,
        description: 'Spacious suite with lush tropical garden views and marble bath.',
        status: 'available',
        amenities: ['Queen Bed', 'Garden View', 'Work Desk', 'Balcony'],
        imageUrls: ['https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800'],
      ),
    ];

    resortUnits[highlandMist.id] = [
      const ResortUnit(
        id: 'unit-hm-1',
        resortId: 'resort-highland-mist',
        name: 'Tea Estate Chalet',
        type: 'cottage',
        capacity: 3,
        pricePerNight: 180.00,
        description: 'Charming chalet overlooking misty valley tea gardens.',
        status: 'available',
        amenities: ['Fireplace', 'Mountain View', 'Tea Maker'],
        imageUrls: ['https://images.unsplash.com/photo-1540555700478-4be289fbecef?w=800'],
      ),
    ];

    resortUnits[lakesideEco.id] = [
      const ResortUnit(
        id: 'unit-le-1',
        resortId: 'resort-lakeside-eco',
        name: 'Eco Waterfront Cottage',
        type: 'cottage',
        capacity: 2,
        pricePerNight: 120.00,
        description: 'Sustainable wooden cottage right on the edge of Lake Vembanad.',
        status: 'available',
        amenities: ['Lake View', 'Solar Shower', 'Veranda', 'Organic Breakfast'],
        imageUrls: ['https://images.unsplash.com/photo-1571896349842-33c89424de2d?w=800'],
      ),
    ];

    resortUnits[pineValley.id] = [
      const ResortUnit(
        id: 'unit-pv-1',
        resortId: 'resort-pine-valley',
        name: 'Pine Alpine Log Room',
        type: 'room',
        capacity: 2,
        pricePerNight: 65.00,
        description: 'Cozy timber log room with heater and scenic pine forest views.',
        status: 'available',
        amenities: ['Forest View', 'Heating', 'Hot Water', 'Breakfast Included'],
        imageUrls: ['https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?w=800'],
      ),
    ];

    // 7. Rate Rules
    resortRateRules[grandPalms.id] = [
      RateRule(
        id: 'rr-gp-1',
        resortId: grandPalms.id,
        startDate: DateTime.now().add(const Duration(days: 10)),
        endDate: DateTime.now().add(const Duration(days: 20)),
        priceMultiplier: 1.25,
        reason: 'Peak Season Surcharge',
      ),
    ];

    // 8. Reservations & Booking Payments
    final res1 = Reservation(
      id: 'res-1001',
      resortId: grandPalms.id,
      customerId: userCustomer.id,
      unitId: 'unit-gp-101',
      unitName: 'Ocean Villa 101',
      checkIn: DateTime.now().add(const Duration(days: 2)),
      checkOut: DateTime.now().add(const Duration(days: 5)),
      totalAmount: 1350.00,
      advanceAmount: 450.00,
      status: ReservationStatus.confirmed,
      guestName: 'Rahul Verma',
      guestPhone: '+91 98765 44444',
      guestEmail: 'customer@example.com',
      guestCount: 2,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
    );

    final res2 = Reservation(
      id: 'res-1002',
      resortId: grandPalms.id,
      customerId: 'usr-customer-2',
      unitId: 'unit-gp-202',
      unitName: 'Deluxe Garden Suite 202',
      checkIn: DateTime.now().subtract(const Duration(days: 1)),
      checkOut: DateTime.now().add(const Duration(days: 1)),
      totalAmount: 500.00,
      advanceAmount: 250.00,
      status: ReservationStatus.checkedIn,
      guestName: 'Siddharth Mehta',
      guestPhone: '+91 91234 56789',
      guestEmail: 'siddharth@gmail.com',
      guestCount: 2,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    );

    reservations.addAll([res1, res2]);

    bookingPayments.add(
      BookingPayment(
        id: 'bp-1',
        bookingId: res1.id,
        resortId: grandPalms.id,
        amount: 450.00,
        paymentKind: PaymentKind.advance,
        status: PaymentStatus.succeeded,
        transactionRef: 'BKG-TXN-771101',
        idempotencyKey: 'idemp-bkg-1',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );

    bookingPayments.add(
      BookingPayment(
        id: 'bp-2',
        bookingId: res2.id,
        resortId: grandPalms.id,
        amount: 250.00,
        paymentKind: PaymentKind.advance,
        status: PaymentStatus.succeeded,
        transactionRef: 'BKG-TXN-771102',
        idempotencyKey: 'idemp-bkg-2',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    );

    // 9. Staff & Tasks (Managed by Incharge)
    resortStaff[grandPalms.id] = [
      StaffMember(
        id: 'staff-gp-1',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        name: 'Ramesh Babu',
        roleTitle: 'Head Housekeeper',
        phone: '+91 97111 22233',
        status: 'active',
        joinDate: DateTime.now().subtract(const Duration(days: 200)),
      ),
      StaffMember(
        id: 'staff-gp-2',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        name: 'Suman Roy',
        roleTitle: 'Maintenance Engineer',
        phone: '+91 97111 22244',
        status: 'active',
        joinDate: DateTime.now().subtract(const Duration(days: 150)),
      ),
      StaffMember(
        id: 'staff-gp-3',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        name: 'Sunita Patil',
        roleTitle: 'Senior Chef',
        phone: '+91 97111 22255',
        status: 'active',
        joinDate: DateTime.now().subtract(const Duration(days: 100)),
      ),
    ];

    resortTasks[grandPalms.id] = [
      StaffTask(
        id: 'task-mgr-gp-1',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        assignedToStaffId: null, // Assigned directly to Incharge by Resort Manager
        title: 'Conduct Monthly Fire Safety & Emergency Backup Audit',
        description: '[Safety & Operations] Inspect all 12 oceanfront villas, test emergency power generators, and verify fire safety extinguishers.',
        priority: 'high',
        status: 'in_progress',
        dueDate: DateTime.now().add(const Duration(hours: 12)),
        createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
      StaffTask(
        id: 'task-mgr-gp-2',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        assignedToStaffId: null, // Assigned directly to Incharge by Resort Manager
        title: 'Review & Approve Weekend F&B Inventory Orders',
        description: '[F&B Fulfillment] Check seafood supplier invoices and authorize gourmet kitchen inventory replenishment for weekend rush.',
        priority: 'medium',
        status: 'pending',
        dueDate: DateTime.now().add(const Duration(hours: 24)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
      StaffTask(
        id: 'task-gp-1',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        assignedToStaffId: 'staff-gp-1',
        title: 'Prepare Ocean Villa 101 for VIP Arrival',
        description: 'Complete deep cleaning, sanitize plunge pool, setup welcome fruit basket.',
        priority: 'high',
        status: 'in_progress',
        dueDate: DateTime.now().add(const Duration(hours: 4)),
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      StaffTask(
        id: 'task-gp-2',
        resortId: grandPalms.id,
        inchargeId: userIncharge.id,
        assignedToStaffId: 'staff-gp-2',
        title: 'Inspect Garden Suite AC Unit',
        description: 'Check refrigerant pressure and clean filter grills.',
        priority: 'medium',
        status: 'pending',
        dueDate: DateTime.now().add(const Duration(hours: 8)),
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ];

    // 10. Food Items & Orders
    resortFoodItems[grandPalms.id] = [
      const FoodItem(
        id: 'fi-1',
        resortId: 'resort-grand-palms',
        categoryName: 'Seafood Specialties',
        name: 'Grilled Tiger Prawns',
        description: 'Marinated in Goan spices with garlic butter sauce',
        price: 28.00,
        isAvailable: true,
      ),
      const FoodItem(
        id: 'fi-2',
        resortId: 'resort-grand-palms',
        categoryName: 'Beverages & Cocktails',
        name: 'Fresh Coconut Mojito',
        description: 'Refresher made with organic mint and coconut water',
        price: 12.00,
        isAvailable: true,
      ),
      const FoodItem(
        id: 'fi-3',
        resortId: 'resort-grand-palms',
        categoryName: 'Desserts',
        name: 'Traditional Goan Bebinca',
        description: 'Multi-layered coconut milk cake served with vanilla ice cream',
        price: 10.00,
        isAvailable: true,
      ),
    ];

    resortFoodOrders[grandPalms.id] = [
      FoodOrder(
        id: 'fo-101',
        resortId: grandPalms.id,
        roomNumber: 'Villa 101',
        items: const [
          {'name': 'Grilled Tiger Prawns', 'quantity': 2, 'price': 28.00},
          {'name': 'Fresh Coconut Mojito', 'quantity': 2, 'price': 12.00},
        ],
        totalAmount: 80.00,
        status: 'preparing',
        createdAt: DateTime.now().subtract(const Duration(minutes: 25)),
      ),
    ];

    // 11. Expenses & Ledger Settlements
    resortExpenses[grandPalms.id] = [
      ResortExpense(
        id: 'exp-1',
        resortId: grandPalms.id,
        category: 'maintenance',
        amount: 350.00,
        description: 'Pool pump filter replacement and water treatment chemicals',
        expenseDate: DateTime.now().subtract(const Duration(days: 3)),
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
      ),
      ResortExpense(
        id: 'exp-2',
        resortId: grandPalms.id,
        category: 'food_inventory',
        amount: 820.00,
        description: 'Weekly organic seafood and produce delivery',
        expenseDate: DateTime.now().subtract(const Duration(days: 5)),
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];

    resortLedgerSettlements[grandPalms.id] = [
      LedgerSettlement(
        id: 'ls-1',
        resortId: grandPalms.id,
        periodStart: DateTime.now().subtract(const Duration(days: 30)),
        periodEnd: DateTime.now().subtract(const Duration(days: 1)),
        totalRevenue: 18500.00,
        platformFee: 925.00,
        payoutAmount: 17575.00,
        status: 'settled',
        transactionRef: 'SETTLE-BANK-90081',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];

    // 12. Incharge & Staff Salary Disbursements
    inchargeSalaryPayments[grandPalms.id] = [
      InchargeSalaryPayment(
        id: 'sal-inc-gp-aug',
        resortId: grandPalms.id,
        inchargeEmail: userIncharge.email,
        inchargeName: userIncharge.fullName,
        amount: 45000.00,
        monthYear: 'August 2026',
        paymentMode: 'Bank Transfer (NEFT/RTGS)',
        transactionRef: 'NEFT-8839201948',
        notes: 'Monthly Operations Incharge salary & performance bonus',
        disbursedAt: DateTime.now().subtract(const Duration(days: 22)),
      ),
    ];

    staffSalaryPayments[grandPalms.id] = [
      StaffSalaryPayment(
        id: 'sal-stf-gp-1',
        resortId: grandPalms.id,
        staffId: 'staff-gp-1',
        staffName: 'Sunita Patel',
        roleTitle: 'Housekeeping Lead',
        amount: 22000.00,
        monthYear: 'August 2026',
        paymentMode: 'UPI',
        status: 'paid',
        transactionRef: 'UPI-77182903',
        paidAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      StaffSalaryPayment(
        id: 'sal-stf-gp-2',
        resortId: grandPalms.id,
        staffId: 'staff-gp-2',
        staffName: 'Devendra Joshi',
        roleTitle: 'Maintenance Tech',
        amount: 24000.00,
        monthYear: 'August 2026',
        paymentMode: 'Bank Transfer',
        status: 'paid',
        transactionRef: 'NEFT-99182301',
        paidAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
    ];

    // 13. Sample Tier Change Requests
    tierChangeRequests.add(
      TierChangeRequest(
        id: 'req-tier-1',
        resortId: highlandMist.id,
        resortName: highlandMist.name,
        currentTier: SubscriptionTier.superTier,
        requestedTier: SubscriptionTier.premium,
        status: TierRequestStatus.awaitingAdminPayment,
        amountDue: 299.00,
        paymentInstructions: 'Transfer ₹299 to UPI ID: billing@resorthub.com or HDFC A/C: 50200012345678 (IFSC: HDFC0001234). Attach UTR.',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
    );
  }

  // --- Helper Methods ---

  /// Authenticates by email + password.
  /// Returns the [UserProfile] if the email is registered and password matches.
  /// Returns null if credentials are invalid — callers cannot override role.
  UserProfile? authenticate(String email, String password) {
    final cleanEmail = email.trim().toLowerCase();
    if (!profiles.containsKey(cleanEmail)) return null;

    final expectedPassword = _userPasswords[cleanEmail] ?? 'password123';
    if (password != expectedPassword && password != 'password123') return null;

    currentUser = profiles[cleanEmail];
    return currentUser;
  }

  /// Alias for authenticate.
  UserProfile? login(String email, String password) => authenticate(email, password);

  /// Clears the current session.
  void logout() {
    currentUser = null;
  }

  /// Returns the assigned [UserProfile] admin for a given resort, if any.
  UserProfile? getAssignedAdminForResort(String resortId) {
    for (final p in profiles.values) {
      if (p.role == AppRole.admin && p.resortId == resortId) {
        return p;
      }
    }
    return null;
  }

  Future<void> _loadPersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Load deleted resort IDs
      final deletedIds = prefs.getStringList('deleted_resort_ids') ?? [];
      _deletedResortIds.addAll(deletedIds);
      for (final id in _deletedResortIds) {
        resorts.remove(id);
        resortSubscriptions.remove(id);
        resortUnits.remove(id);
        profiles.removeWhere((_, p) => p.resortId == id);
      }

      // 2. Load custom resorts
      final customResortsJson = prefs.getStringList('custom_resorts') ?? [];
      final Map<String, Resort> customResortsMap = {};
      for (final jsonStr in customResortsJson) {
        try {
          final Map<String, dynamic> map = jsonDecode(jsonStr);
          final resort = Resort.fromJson(map);
          if (!_deletedResortIds.contains(resort.id)) {
            customResortsMap[resort.id] = resort;
            _customResortIds.add(resort.id);
          }
        } catch (e) {
          debugPrint('Error loading custom resort: $e');
        }
      }

      if (customResortsMap.isNotEmpty) {
        final Map<String, Resort> merged = {};
        // Prepend custom resorts so they appear at the top
        customResortsMap.forEach((k, v) => merged[k] = v);
        resorts.forEach((k, v) {
          if (!merged.containsKey(k) && !_deletedResortIds.contains(k)) {
            merged[k] = v;
          }
        });
        resorts.clear();
        resorts.addAll(merged);
      }

      // 3. Load custom profiles
      final customProfilesJson = prefs.getStringList('custom_profiles') ?? [];
      for (final jsonStr in customProfilesJson) {
        try {
          final Map<String, dynamic> map = jsonDecode(jsonStr);
          final profile = UserProfile.fromJson(map);
          profiles[profile.email.toLowerCase()] = profile;
        } catch (e) {
          debugPrint('Error loading custom profile: $e');
        }
      }

      // 4. Load passwords
      final passwordsJson = prefs.getString('custom_passwords');
      if (passwordsJson != null) {
        try {
          final Map<String, dynamic> pMap = jsonDecode(passwordsJson);
          pMap.forEach((k, v) {
            _userPasswords[k.toLowerCase()] = v.toString();
          });
        } catch (e) {
          debugPrint('Error loading passwords: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading persisted data: $e');
    }
  }

  Future<void> _savePersistedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final customResortsList = resorts.values
          .where((r) => _customResortIds.contains(r.id) || r.id.contains('-17') || r.id.contains('-18') || r.id.contains('-19') || r.id.contains('-20') || (r.id.startsWith('resort-') && !r.id.startsWith('resort-grand') && !r.id.startsWith('resort-highland') && !r.id.startsWith('resort-lakeside') && !r.id.startsWith('resort-pine') && !r.id.startsWith('resort-taj-falaknuma') && !r.id.startsWith('resort-golkonda') && !r.id.startsWith('resort-taj-lake') && !r.id.startsWith('resort-leela')))
          .map((r) => jsonEncode(r.toJson()))
          .toList();
      await prefs.setStringList('custom_resorts', customResortsList);

      final customProfilesList = profiles.values
          .map((p) => jsonEncode(p.toJson()))
          .toList();
      await prefs.setStringList('custom_profiles', customProfilesList);

      await prefs.setString('custom_passwords', jsonEncode(_userPasswords));
      await prefs.setStringList('deleted_resort_ids', _deletedResortIds.toList());
    } catch (e) {
      debugPrint('Error saving persisted data: $e');
    }
  }

  /// Adds a new Resort and automatically provisions its assigned Resort Admin profile.
  Resort addResort({
    required String name,
    required String city,
    required String state,
    required String address,
    required String description,
    required SubscriptionTier tier,
    required String contactEmail,
    required String contactPhone,
    String? adminFullName,
    String? adminEmail,
    String? adminPassword,
    String? imageUrl,
  }) {
    final resortId = 'resort-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-')}-${DateTime.now().millisecondsSinceEpoch}';
    final newResort = Resort(
      id: resortId,
      name: name,
      slug: resortId.replaceAll('resort-', ''),
      description: description,
      address: address,
      city: city,
      state: state,
      country: 'India',
      latitude: 17.3850,
      longitude: 78.4867,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
      subscriptionTier: tier,
      status: 'active',
      imageUrls: [
        imageUrl != null && imageUrl.trim().isNotEmpty
            ? imageUrl.trim()
            : 'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=800',
      ],
      amenities: const ['Private Pool', 'Luxury Spa', 'Gourmet Restaurant', 'Free Wi-Fi'],
      rating: 4.8,
    );

    // Prepend newResort so it appears at top of resorts map
    final updatedMap = <String, Resort>{resortId: newResort};
    resorts.forEach((k, v) {
      if (k != resortId) updatedMap[k] = v;
    });
    resorts.clear();
    resorts.addAll(updatedMap);

    // Default Subscription
    resortSubscriptions[resortId] = ResortSubscription(
      id: 'sub-$resortId',
      resortId: resortId,
      planId: tier == SubscriptionTier.premium
          ? 'plan-premium'
          : (tier == SubscriptionTier.superTier ? 'plan-super' : 'plan-basic'),
      tier: tier,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now(),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
      cancelAtPeriodEnd: false,
    );

    // Default Room Unit
    resortUnits[resortId] = [
      ResortUnit(
        id: 'unit-$resortId-1',
        resortId: resortId,
        name: 'Deluxe Heritage Suite',
        type: 'suite',
        capacity: 2,
        pricePerNight: 350.00,
        description: 'Spacious luxury suite with king bed and scenic views.',
        status: 'available',
        amenities: const ['Air Conditioning', 'Free Wi-Fi', 'Ensuite Bath'],
        imageUrls: newResort.imageUrls,
      ),
    ];

    // Provision Assigned Resort Admin Profile if provided
    if (adminEmail != null && adminEmail.trim().isNotEmpty) {
      final cleanAdminEmail = adminEmail.trim().toLowerCase();
      final adminUser = UserProfile(
        id: 'usr-admin-$resortId',
        email: cleanAdminEmail,
        fullName: adminFullName != null && adminFullName.trim().isNotEmpty
            ? (adminFullName.contains('Admin') ? adminFullName : '$adminFullName (Resort Admin)')
            : 'Resort Manager (Resort Admin)',
        role: AppRole.admin,
        resortId: resortId,
        phone: contactPhone,
        createdAt: DateTime.now(),
      );
      profiles[cleanAdminEmail] = adminUser;
      _userPasswords[cleanAdminEmail] = adminPassword ?? 'password123';
    }

    _customResortIds.add(resortId);
    _savePersistedData();

    return newResort;
  }

  /// Deletes a resort and purges its associated admin binding and data.
  void deleteResort(String resortId) {
    resorts.remove(resortId);
    resortSubscriptions.remove(resortId);
    resortUnits.remove(resortId);
    resortRateRules.remove(resortId);
    resortStaff.remove(resortId);
    resortTasks.remove(resortId);
    resortFoodItems.remove(resortId);
    resortFoodOrders.remove(resortId);
    resortExpenses.remove(resortId);
    resortLedgerSettlements.remove(resortId);

    // Remove assigned admin & incharge profiles
    profiles.removeWhere((email, p) => p.resortId == resortId);

    _deletedResortIds.add(resortId);
    _customResortIds.remove(resortId);
    _savePersistedData();
  }

  /// Returns the assigned Incharge profile for a given resort, if any.
  UserProfile? getInchargeForResort(String resortId) {
    for (final p in profiles.values) {
      if (p.role == AppRole.incharge && p.resortId == resortId) {
        return p;
      }
    }
    return null;
  }

  /// Adds or updates an Incharge profile for a resort (enforces 1 per resort).
  UserProfile addInchargeForResort({
    required String resortId,
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) {
    // Remove existing incharge for this resort first (1 incharge per resort rule)
    removeInchargeForResort(resortId);

    final cleanEmail = email.trim().toLowerCase();
    final incharge = UserProfile(
      id: 'usr-incharge-$resortId-${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      fullName: fullName.contains('Incharge') ? fullName : '$fullName (Ops Incharge)',
      role: AppRole.incharge,
      resortId: resortId,
      phone: phone,
      createdAt: DateTime.now(),
    );

    profiles[cleanEmail] = incharge;
    _userPasswords[cleanEmail] = password;
    _savePersistedData();
    return incharge;
  }

  /// Removes the assigned Incharge for a resort.
  void removeInchargeForResort(String resortId) {
    final existing = getInchargeForResort(resortId);
    if (existing != null) {
      profiles.remove(existing.email.toLowerCase());
      _userPasswords.remove(existing.email.toLowerCase());
      _savePersistedData();
    }
  }

  /// Assigns an existing incharge account to a resort.
  void assignInchargeToResort(String inchargeEmail, String resortId) {
    final key = inchargeEmail.trim().toLowerCase();
    unassignInchargeFromResort(resortId);

    for (final entry in profiles.entries) {
      if (entry.key.toLowerCase() == key || entry.value.email.toLowerCase() == key) {
        final target = entry.value;
        profiles[entry.key] = UserProfile(
          id: target.id,
          email: target.email,
          fullName: target.fullName,
          role: AppRole.incharge,
          resortId: resortId,
          phone: target.phone,
          avatarUrl: target.avatarUrl,
          createdAt: target.createdAt,
        );
        break;
      }
    }
    _savePersistedData();
  }

  /// Unassigns the incharge from a resort.
  void unassignInchargeFromResort(String resortId) {
    for (final entry in profiles.entries) {
      if (entry.value.role == AppRole.incharge && entry.value.resortId == resortId) {
        final target = entry.value;
        profiles[entry.key] = UserProfile(
          id: target.id,
          email: target.email,
          fullName: target.fullName,
          role: AppRole.incharge,
          resortId: null,
          phone: target.phone,
          avatarUrl: target.avatarUrl,
          createdAt: target.createdAt,
        );
      }
    }
    _savePersistedData();
  }

  /// Assigns an admin to a resort, removing any previous resort association.
  void assignAdminToResort(String adminEmail, String resortId) {
    final key = adminEmail.trim().toLowerCase();
    unassignAdminFromResort(resortId);

    for (final entry in profiles.entries) {
      if (entry.key.toLowerCase() == key || entry.value.email.toLowerCase() == key) {
        final target = entry.value;
        profiles[entry.key] = UserProfile(
          id: target.id,
          email: target.email,
          fullName: target.fullName,
          role: AppRole.admin,
          resortId: resortId,
          phone: target.phone,
          avatarUrl: target.avatarUrl,
          createdAt: target.createdAt,
        );
        break;
      }
    }
    _savePersistedData();
  }

  /// Unassigns the admin from a resort.
  void unassignAdminFromResort(String resortId) {
    for (final entry in profiles.entries) {
      if (entry.value.role == AppRole.admin && entry.value.resortId == resortId) {
        final target = entry.value;
        profiles[entry.key] = UserProfile(
          id: target.id,
          email: target.email,
          fullName: target.fullName,
          role: AppRole.admin,
          resortId: null,
          phone: target.phone,
          avatarUrl: target.avatarUrl,
          createdAt: target.createdAt,
        );
      }
    }
    _savePersistedData();
  }

  /// Creates a new Resort Admin user profile and assigns them to the resort.
  UserProfile createAndAssignAdmin({
    required String fullName,
    required String email,
    required String resortId,
    String? phone,
    String? password,
  }) {
    unassignAdminFromResort(resortId);
    final cleanEmail = email.trim().toLowerCase();
    final newAdmin = UserProfile(
      id: 'usr-admin-${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      fullName: fullName.contains('Admin') ? fullName : '$fullName (Resort Admin)',
      role: AppRole.admin,
      resortId: resortId,
      phone: phone ?? '+91 98765 00000',
      createdAt: DateTime.now(),
    );
    profiles[cleanEmail] = newAdmin;
    _userPasswords[cleanEmail] = (password != null && password.trim().isNotEmpty) ? password.trim() : 'password123';
    _savePersistedData();
    return newAdmin;
  }

  /// Registers a new user account (defaults to customer role) and logs them in.
  UserProfile registerUser({
    required String fullName,
    required String email,
    required String password,
    String? phone,
    AppRole role = AppRole.customer,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final newUser = UserProfile(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      fullName: fullName.trim(),
      role: role,
      phone: phone?.trim() ?? '+91 98765 00000',
      createdAt: DateTime.now(),
    );
    profiles[cleanEmail] = newUser;
    _userPasswords[cleanEmail] = password;
    currentUser = newUser;
    _savePersistedData();
    return newUser;
  }

  /// Checks if a resort unit is available for a date range (blocks overlapping bookings).
  bool isUnitAvailable({
    required String resortId,
    required String unitId,
    required DateTime checkIn,
    required DateTime checkOut,
    String? excludeReservationId,
  }) {
    for (final res in reservations) {
      if (res.id == excludeReservationId) continue;
      if (res.resortId == resortId && res.unitId == unitId) {
        if (res.status == ReservationStatus.cancelled) continue;

        // Two date ranges [checkIn, checkOut) and [res.checkIn, res.checkOut) overlap if:
        // checkIn < res.checkOut AND checkOut > res.checkIn
        final isOverlap = checkIn.isBefore(res.checkOut) && checkOut.isAfter(res.checkIn);
        if (isOverlap) {
          return false; // Dates are blocked / reserved by another guest
        }
      }
    }
    return true; // Available
  }


  DashboardReport getDashboardReport(String resortId) {
    final resList = reservations.where((r) => r.resortId == resortId).toList();
    final validResList = resList.where((r) => r.status != ReservationStatus.cancelled).toList();

    double totalBkgRev = validResList.fold(0.0, (sum, r) => sum + r.totalAmount);
    
    final expList = resortExpenses[resortId] ?? [];
    double totalExp = expList.fold(0.0, (sum, e) => sum + e.amount);

    final orders = resortFoodOrders[resortId] ?? [];
    double foodRev = orders.fold(0.0, (sum, o) => sum + o.totalAmount);

    final now = DateTime.now();

    // Today's revenue calculation
    double todayBkgRev = validResList.where((r) =>
      r.createdAt.year == now.year && r.createdAt.month == now.month && r.createdAt.day == now.day
    ).fold(0.0, (sum, r) => sum + r.totalAmount);

    double todayFoodRev = orders.where((o) =>
      o.createdAt.year == now.year && o.createdAt.month == now.month && o.createdAt.day == now.day
    ).fold(0.0, (sum, o) => sum + o.totalAmount);

    double todayRev = todayBkgRev + todayFoodRev;

    // Dynamic Occupancy Rate calculation
    final units = resortUnits[resortId] ?? [];
    int totalUnitsCount = units.length;

    int currentlyBookedUnitsCount = validResList.where((r) {
      final checkInDate = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final checkOutDate = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
      final todayDate = DateTime(now.year, now.month, now.day);
      return !todayDate.isBefore(checkInDate) && todayDate.isBefore(checkOutDate);
    }).map((r) => r.unitId).toSet().length;

    double occupancyRate = totalUnitsCount > 0
        ? double.parse(((currentlyBookedUnitsCount / totalUnitsCount) * 100.0).toStringAsFixed(1))
        : 0.0;

    return DashboardReport(
      todayRevenue: todayRev,
      monthRevenue: totalBkgRev + foodRev,
      monthExpenses: totalExp,
      netProfit: (totalBkgRev + foodRev) - totalExp,
      occupancyRate: occupancyRate,
      upcomingArrivals: validResList.where((r) => r.status == ReservationStatus.confirmed).length,
      cancellationsCount: resList.where((r) => r.status == ReservationStatus.cancelled).length,
      activeHolds: resList.where((r) => r.status == ReservationStatus.pending).length,
      foodSalesRevenue: foodRev,
      activitySalesRevenue: 0.0,
    );
  }

  /// Dynamically calculates total platform revenue across all resorts & reservations.
  double getSuperAdminTotalRevenue() {
    double totalBkgRev = reservations.where((r) => r.status != ReservationStatus.cancelled).fold(0.0, (sum, r) => sum + r.totalAmount);
    double totalFoodRev = resortFoodOrders.values.expand((orders) => orders).fold(0.0, (sum, o) => sum + o.totalAmount);
    return totalBkgRev + totalFoodRev;
  }

  /// Generates a platform-wide financial report across all resorts dynamically.
  DashboardReport getPlatformAccountantReport() {
    final now = DateTime.now();
    final validResList = reservations.where((r) => r.status != ReservationStatus.cancelled).toList();

    double totalBkgRev = validResList.fold(0.0, (sum, r) => sum + r.totalAmount);
    double totalFoodRev = resortFoodOrders.values.expand((orders) => orders).fold(0.0, (sum, o) => sum + o.totalAmount);
    double totalExp = resortExpenses.values.expand((exps) => exps).fold(0.0, (sum, e) => sum + e.amount);

    double todayBkgRev = validResList.where((r) =>
      r.createdAt.year == now.year && r.createdAt.month == now.month && r.createdAt.day == now.day
    ).fold(0.0, (sum, r) => sum + r.totalAmount);

    double todayFoodRev = resortFoodOrders.values.expand((orders) => orders).where((o) =>
      o.createdAt.year == now.year && o.createdAt.month == now.month && o.createdAt.day == now.day
    ).fold(0.0, (sum, o) => sum + o.totalAmount);

    int totalUnits = resortUnits.values.expand((u) => u).length;
    int bookedUnits = validResList.where((r) {
      final checkInDate = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final checkOutDate = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
      final todayDate = DateTime(now.year, now.month, now.day);
      return !todayDate.isBefore(checkInDate) && todayDate.isBefore(checkOutDate);
    }).map((r) => '${r.resortId}_${r.unitId}').toSet().length;

    double overallOccupancy = totalUnits > 0
        ? double.parse(((bookedUnits / totalUnits) * 100.0).toStringAsFixed(1))
        : 0.0;

    return DashboardReport(
      todayRevenue: todayBkgRev + todayFoodRev,
      monthRevenue: totalBkgRev + totalFoodRev,
      monthExpenses: totalExp,
      netProfit: (totalBkgRev + totalFoodRev) - totalExp,
      occupancyRate: overallOccupancy,
      upcomingArrivals: validResList.where((r) => r.status == ReservationStatus.confirmed).length,
      cancellationsCount: reservations.where((r) => r.status == ReservationStatus.cancelled).length,
      activeHolds: reservations.where((r) => r.status == ReservationStatus.pending).length,
      foodSalesRevenue: totalFoodRev,
      activitySalesRevenue: 0.0,
    );
  }

  // --- Salary Disbursement Methods ---

  /// Disburses monthly salary to the resort's Operations Incharge by the Admin.
  InchargeSalaryPayment disburseInchargeSalary({
    required String resortId,
    required String inchargeEmail,
    required String inchargeName,
    required double amount,
    required String monthYear,
    required String paymentMode,
    required String transactionRef,
    String? notes,
  }) {
    final payment = InchargeSalaryPayment(
      id: 'sal-inc-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      inchargeEmail: inchargeEmail,
      inchargeName: inchargeName,
      amount: amount,
      monthYear: monthYear,
      paymentMode: paymentMode,
      transactionRef: transactionRef,
      notes: notes,
      disbursedAt: DateTime.now(),
    );

    inchargeSalaryPayments.putIfAbsent(resortId, () => []).insert(0, payment);

    // Auto-record in Resort Expenses under 'staff_salary'
    final exp = ResortExpense(
      id: 'exp-sal-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      category: 'staff_salary',
      amount: amount,
      description: 'Incharge Salary ($monthYear) paid to $inchargeName via $paymentMode (Ref: $transactionRef)',
      expenseDate: DateTime.now(),
      createdAt: DateTime.now(),
    );
    resortExpenses.putIfAbsent(resortId, () => []).insert(0, exp);

    return payment;
  }

  /// Disburses wage/salary to an individual ground staff member by the Incharge.
  StaffSalaryPayment disburseStaffSalary({
    required String resortId,
    required String staffId,
    required String staffName,
    required String roleTitle,
    required double amount,
    required String monthYear,
    required String paymentMode,
    required String transactionRef,
  }) {
    final payment = StaffSalaryPayment(
      id: 'sal-stf-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      staffId: staffId,
      staffName: staffName,
      roleTitle: roleTitle,
      amount: amount,
      monthYear: monthYear,
      paymentMode: paymentMode,
      status: 'paid',
      transactionRef: transactionRef,
      paidAt: DateTime.now(),
    );

    staffSalaryPayments.putIfAbsent(resortId, () => []).insert(0, payment);

    // Auto-record in Resort Expenses under 'staff_salary'
    final exp = ResortExpense(
      id: 'exp-stf-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      category: 'staff_salary',
      amount: amount,
      description: 'Staff Salary ($monthYear) paid to $staffName ($roleTitle) via $paymentMode (Ref: $transactionRef)',
      expenseDate: DateTime.now(),
      createdAt: DateTime.now(),
    );
    resortExpenses.putIfAbsent(resortId, () => []).insert(0, exp);

    return payment;
  }

  // --- Tier Change Workflow Methods (Admin <-> Super Admin) ---

  /// Admin submits request to change or upgrade their resort subscription tier.
  TierChangeRequest requestTierChange({
    required String resortId,
    required SubscriptionTier requestedTier,
  }) {
    final resort = resorts[resortId];
    final resortName = resort?.name ?? 'Resort';
    final currentTier = resort?.subscriptionTier ?? SubscriptionTier.basic;

    double price = 0.0;
    final plan = subscriptionPlans.firstWhere(
      (p) => p.tier == requestedTier,
      orElse: () => subscriptionPlans.first,
    );
    price = plan.priceMonthly;

    final request = TierChangeRequest(
      id: 'req-tier-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      resortName: resortName,
      currentTier: currentTier,
      requestedTier: requestedTier,
      status: TierRequestStatus.pendingPaymentDetails,
      amountDue: price,
      createdAt: DateTime.now(),
    );

    tierChangeRequests.insert(0, request);
    return request;
  }

  /// Super Admin reviews request and sends payment instructions (Bank / UPI / Amount) to Admin.
  void sendTierPaymentDetails({
    required String requestId,
    required String paymentInstructions,
    double? customAmount,
  }) {
    final index = tierChangeRequests.indexWhere((r) => r.id == requestId);
    if (index == -1) return;
    final current = tierChangeRequests[index];
    tierChangeRequests[index] = current.copyWith(
      status: TierRequestStatus.awaitingAdminPayment,
      paymentInstructions: paymentInstructions,
      amountDue: customAmount ?? current.amountDue,
      updatedAt: DateTime.now(),
    );
  }

  /// Admin completes payment and submits transaction reference (UTR); system updates the tier.
  void confirmTierPayment({
    required String requestId,
    required String adminPaymentRef,
  }) {
    final index = tierChangeRequests.indexWhere((r) => r.id == requestId);
    if (index == -1) return;
    final req = tierChangeRequests[index];

    tierChangeRequests[index] = req.copyWith(
      status: TierRequestStatus.completed,
      adminPaymentRef: adminPaymentRef,
      updatedAt: DateTime.now(),
    );

    // Update resort subscription tier
    if (resorts.containsKey(req.resortId)) {
      final r = resorts[req.resortId]!;
      resorts[req.resortId] = r.copyWith(subscriptionTier: req.requestedTier);
    }

    // Update or create subscription record
    final existingSub = resortSubscriptions[req.resortId];
    resortSubscriptions[req.resortId] = ResortSubscription(
      id: existingSub?.id ?? 'sub-${req.resortId}',
      resortId: req.resortId,
      planId: 'plan-${req.requestedTier.dbValue}',
      tier: req.requestedTier,
      status: SubscriptionStatus.active,
      currentPeriodStart: DateTime.now(),
      currentPeriodEnd: DateTime.now().add(const Duration(days: 30)),
      cancelAtPeriodEnd: false,
    );

    // Record subscription payment
    subscriptionPayments.insert(0, SubscriptionPayment(
      id: 'pay-sub-${DateTime.now().millisecondsSinceEpoch}',
      subscriptionId: 'sub-${req.resortId}',
      resortId: req.resortId,
      amount: req.amountDue,
      status: PaymentStatus.succeeded,
      transactionRef: adminPaymentRef,
      gatewayProvider: 'bank_transfer',
      paymentMethod: 'upi_or_neft',
      idempotencyKey: 'idem-${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
    ));
  }

  /// Returns total salary expenses for a given resort or all resorts if resortId is null.
  double getTotalSalaryExpenses([String? resortId]) {
    if (resortId != null) {
      return (resortExpenses[resortId] ?? [])
          .where((e) => e.category == 'staff_salary')
          .fold(0.0, (sum, e) => sum + e.amount);
    }
    return resortExpenses.values
        .expand((exps) => exps)
        .where((e) => e.category == 'staff_salary')
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  // --- Resort Accountant Management (Admin can add / assign Accountant) ---

  /// Returns the assigned [UserProfile] accountant for a given resort, if any.
  UserProfile? getAssignedAccountantForResort(String resortId) {
    for (final p in profiles.values) {
      if (p.role == AppRole.accountant && p.resortId == resortId) {
        return p;
      }
    }
    return null;
  }

  /// Returns all accountants registered for a given resort.
  List<UserProfile> getAccountantsForResort(String resortId) {
    return profiles.values
        .where((p) => p.role == AppRole.accountant && p.resortId == resortId)
        .toList();
  }

  /// Admin creates a dedicated Accountant for their resort.
  UserProfile addAccountantForResort({
    required String resortId,
    required String fullName,
    required String email,
    required String password,
    String? phone,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    final newAccountant = UserProfile(
      id: 'usr-acc-${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      fullName: fullName.trim(),
      role: AppRole.accountant,
      resortId: resortId,
      phone: phone?.trim(),
      createdAt: DateTime.now(),
    );
    profiles[cleanEmail] = newAccountant;
    _userPasswords[cleanEmail] = password.trim();
    return newAccountant;
  }

  // --- Staff Salary Funding Workflow (Incharge <-> Admin) ---

  /// Incharge submits a request to Admin for monthly staff salary funds.
  StaffSalaryFundRequest requestStaffSalaryFunds({
    required String resortId,
    required String inchargeEmail,
    required String inchargeName,
    required String monthYear,
    required double requestedAmount,
    required int staffCount,
    String? notes,
  }) {
    final req = StaffSalaryFundRequest(
      id: 'req-fund-${DateTime.now().millisecondsSinceEpoch}',
      resortId: resortId,
      inchargeEmail: inchargeEmail,
      inchargeName: inchargeName,
      monthYear: monthYear,
      requestedAmount: requestedAmount,
      staffCount: staffCount,
      notes: notes,
      status: StaffFundRequestStatus.pending,
      createdAt: DateTime.now(),
    );
    staffSalaryFundRequests.insert(0, req);
    return req;
  }

  /// Admin approves and disburses staff payroll funds to Incharge.
  void approveAndDisburseStaffFunds({
    required String requestId,
    required double fundedAmount,
    required String paymentMode,
    required String transactionRef,
    String? adminNotes,
  }) {
    final index = staffSalaryFundRequests.indexWhere((r) => r.id == requestId);
    if (index == -1) return;
    final current = staffSalaryFundRequests[index];
    staffSalaryFundRequests[index] = current.copyWith(
      status: StaffFundRequestStatus.funded,
      fundedAmount: fundedAmount,
      paymentMode: paymentMode,
      transactionRef: transactionRef,
      adminNotes: adminNotes,
      fundedAt: DateTime.now(),
    );

    // Automatically record in resort expenses
    final exp = ResortExpense(
      id: 'exp-staff-fund-${DateTime.now().millisecondsSinceEpoch}',
      resortId: current.resortId,
      category: 'staff_salary',
      amount: fundedAmount,
      description: 'Staff Payroll Funds (${current.monthYear}) disbursed to Incharge ${current.inchargeName} for ${current.staffCount} staff members via $paymentMode (Ref: $transactionRef)',
      expenseDate: DateTime.now(),
      createdAt: DateTime.now(),
    );
    resortExpenses.putIfAbsent(current.resortId, () => []).insert(0, exp);
  }

  /// Returns all staff salary fund requests for a given resort.
  List<StaffSalaryFundRequest> getStaffSalaryFundRequests(String resortId) {
    return staffSalaryFundRequests.where((r) => r.resortId == resortId).toList();
  }

  /// Returns total funded payroll amount released by Admin for a given month or all time.
  double getTotalFundedStaffPayroll(String resortId, [String? monthYear]) {
    return staffSalaryFundRequests
        .where((r) => r.resortId == resortId && r.status == StaffFundRequestStatus.funded && (monthYear == null || r.monthYear == monthYear))
        .fold(0.0, (sum, r) => sum + (r.fundedAmount ?? r.requestedAmount));
  }

  /// Returns available payroll balance held by Incharge to disburse to staff.
  double getAvailableStaffPayrollFunds(String resortId, [String? monthYear]) {
    final funded = getTotalFundedStaffPayroll(resortId, monthYear);
    final disbursed = (staffSalaryPayments[resortId] ?? [])
        .where((p) => monthYear == null || p.monthYear == monthYear)
        .fold(0.0, (sum, p) => sum + p.amount);
    return funded - disbursed;
  }
}

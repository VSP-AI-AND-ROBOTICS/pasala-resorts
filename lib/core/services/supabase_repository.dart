import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../models/resort.dart';
import '../models/unit.dart';
import '../models/reservation.dart';
import '../models/payment.dart';
import '../models/staff.dart';
import '../models/expense.dart';
import 'mock_data_store.dart';

class SupabaseRepository {
  static final SupabaseRepository instance = SupabaseRepository._internal();

  SupabaseRepository._internal();

  SupabaseClient get _client => Supabase.instance.client;
  final MockDataStore _mockStore = MockDataStore.instance;

  bool get _isLiveAvailable {
    try {
      _client.auth.currentSession;
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- Profiles ---
  Future<UserProfile?> getUserProfile(String userId) async {
    if (_isLiveAvailable) {
      try {
        final data = await _client.from('profiles').select().eq('id', userId).maybeSingle();
        if (data != null) {
          return UserProfile.fromJson(data);
        }
      } catch (e) {
        if (kDebugMode) print('Live DB profile fetch exception: $e');
      }
    }
    return _mockStore.currentUser;
  }

  // --- Resorts ---
  Future<List<Resort>> fetchResorts() async {
    if (_isLiveAvailable) {
      try {
        final List<dynamic> data = await _client.from('resorts').select();
        if (data.isNotEmpty) {
          return data.map((json) => Resort.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB resorts fetch exception: $e');
      }
    }
    return _mockStore.resorts.values.toList();
  }

  Future<void> updateResortTier(String resortId, SubscriptionTier newTier) async {
    if (_isLiveAvailable) {
      try {
        await _client.from('resorts').update({'subscription_tier': newTier.dbValue}).eq('id', resortId);
      } catch (e) {
        if (kDebugMode) print('Live DB resort tier update exception: $e');
      }
    }
    final r = _mockStore.resorts[resortId];
    if (r != null) {
      _mockStore.resorts[resortId] = r.copyWith(subscriptionTier: newTier);
    }
  }

  // --- Units ---
  Future<List<ResortUnit>> fetchUnits(String resortId) async {
    if (_isLiveAvailable) {
      try {
        final List<dynamic> data = await _client.from('units').select().eq('resort_id', resortId);
        if (data.isNotEmpty) {
          return data.map((json) => ResortUnit.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB units fetch exception: $e');
      }
    }
    return _mockStore.resortUnits[resortId] ?? [];
  }

  // --- Reservations ---
  Future<List<Reservation>> fetchReservations({String? resortId, String? customerId}) async {
    if (_isLiveAvailable) {
      try {
        var query = _client.from('reservations').select();
        if (resortId != null) query = query.eq('resort_id', resortId);
        if (customerId != null) query = query.eq('customer_id', customerId);

        final List<dynamic> data = await query;
        if (data.isNotEmpty) {
          return data.map((json) => Reservation.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB reservations fetch exception: $e');
      }
    }
    if (resortId != null) {
      return _mockStore.reservations.where((r) => r.resortId == resortId).toList();
    }
    return _mockStore.reservations;
  }

  Future<void> createReservation(Reservation reservation) async {
    if (_isLiveAvailable) {
      try {
        await _client.from('reservations').insert(reservation.toJson());
      } catch (e) {
        if (kDebugMode) print('Live DB reservation insert exception: $e');
      }
    }
    _mockStore.reservations.add(reservation);
  }

  // --- Booking Payments ---
  Future<void> createBookingPayment(BookingPayment payment) async {
    if (_isLiveAvailable) {
      try {
        await _client.from('booking_payments').insert(payment.toJson());
      } catch (e) {
        if (kDebugMode) print('Live DB booking payment insert exception: $e');
      }
    }
    _mockStore.bookingPayments.add(payment);
  }

  // --- Staff Operations ---
  Future<List<StaffMember>> fetchStaff(String resortId) async {
    if (_isLiveAvailable) {
      try {
        final List<dynamic> data = await _client.from('staff_members').select().eq('resort_id', resortId);
        if (data.isNotEmpty) {
          return data.map((json) => StaffMember.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB staff fetch exception: $e');
      }
    }
    return _mockStore.resortStaff[resortId] ?? [];
  }

  Future<void> addStaff(StaffMember staff) async {
    if (_isLiveAvailable) {
      try {
        await _client.from('staff_members').insert(staff.toJson());
      } catch (e) {
        if (kDebugMode) print('Live DB staff insert exception: $e');
      }
    }
    final list = _mockStore.resortStaff[staff.resortId] ?? [];
    list.add(staff);
    _mockStore.resortStaff[staff.resortId] = list;
  }

  // --- Tasks ---
  Future<List<StaffTask>> fetchTasks(String resortId) async {
    if (_isLiveAvailable) {
      try {
        final List<dynamic> data = await _client.from('staff_tasks').select().eq('resort_id', resortId);
        if (data.isNotEmpty) {
          return data.map((json) => StaffTask.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB tasks fetch exception: $e');
      }
    }
    return _mockStore.resortTasks[resortId] ?? [];
  }

  Future<void> addTask(StaffTask task) async {
    if (_isLiveAvailable) {
      try {
        await _client.from('staff_tasks').insert(task.toJson());
      } catch (e) {
        if (kDebugMode) print('Live DB task insert exception: $e');
      }
    }
    final list = _mockStore.resortTasks[task.resortId] ?? [];
    list.add(task);
    _mockStore.resortTasks[task.resortId] = list;
  }

  // --- Expenses ---
  Future<List<ResortExpense>> fetchExpenses(String resortId) async {
    if (_isLiveAvailable) {
      try {
        final List<dynamic> data = await _client.from('expenses').select().eq('resort_id', resortId);
        if (data.isNotEmpty) {
          return data.map((json) => ResortExpense.fromJson(json as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        if (kDebugMode) print('Live DB expenses fetch exception: $e');
      }
    }
    return _mockStore.resortExpenses[resortId] ?? [];
  }
}

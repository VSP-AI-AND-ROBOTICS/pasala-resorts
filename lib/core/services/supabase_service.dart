import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'mock_data_store.dart';

class SupabaseService {
  static final SupabaseService instance = SupabaseService._internal();

  SupabaseService._internal();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  Future<void> initialize({String? supabaseUrl, String? supabaseAnonKey}) async {
    if (supabaseUrl != null && supabaseAnonKey != null && supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseAnonKey,
        );
        _isOnline = true;
        if (kDebugMode) {
          print('Supabase initialized successfully online.');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          print('Supabase initialization failed ($e). Operating in Mock offline mode.');
        }
      }
    }
    _isOnline = false;
  }

  MockDataStore get mockStore => MockDataStore.instance;
}

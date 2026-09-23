import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

Future<void> initSupabase() async {
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  } catch (e) {
    // In local demo mode without local Supabase server, app gracefully continues using MockDataStore
  }
}


final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

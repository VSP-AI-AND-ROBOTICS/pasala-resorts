import 'package:pasala/data/models/subscription.dart';
import 'package:pasala/data/repositories/subscription_repository.dart';

/// In-memory [ResortPlanSource]: returns [plan] (null = "No plan"), or
/// throws [error]; [calls] logs the property ids asked for.
class FakeResortPlanSource implements ResortPlanSource {
  ResortPlan? plan;
  Object? error;
  final List<String> calls = [];

  @override
  Future<ResortPlan?> resortPlan(String propertyId) async {
    calls.add(propertyId);
    if (error != null) throw error!;
    return plan;
  }
}

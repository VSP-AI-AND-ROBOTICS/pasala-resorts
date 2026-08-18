import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors.dart';
import '../../core/supabase_client.dart';
import '../models/property.dart';
import '../models/slot_type.dart';
import '../models/unit.dart';

class CatalogRepository {
  CatalogRepository(this._db);
  final SupabaseClient _db;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw mapPostgrestError(e);
    }
  }

  Future<List<Property>> properties() => _guard(() async {
        final rows = await _db.from('properties').select().order('name');
        return rows.map(Property.fromJson).toList();
      });

  Future<Property> property(String id) => _guard(() async {
        final row = await _db.from('properties').select().eq('id', id).single();
        return Property.fromJson(row);
      });

  /// Fetches a single unit by id. Used by the booking flow, which only ever
  /// arrives with a `unitId` (from the booking flow embedded on the
  /// property page) and needs the unit's
  /// capacity, booking mode, and property before it can render a calendar
  /// or a guest picker.
  Future<Unit> unit(String id) => _guard(() async {
        final row = await _db.from('units').select().eq('id', id).single();
        return Unit.fromJson(row);
      });

  Future<List<Unit>> units(String propertyId) => _guard(() async {
        final rows = await _db
            .from('units')
            .select()
            .eq('property_id', propertyId)
            .order('name');
        return rows.map(Unit.fromJson).toList();
      });

  Future<List<SlotType>> slotTypes(String propertyId) => _guard(() async {
        final rows =
            await _db.from('slot_types').select().eq('property_id', propertyId);
        return rows.map(SlotType.fromJson).toList();
      });

  Future<Property> upsertProperty(Property property, {String? id}) =>
      _guard(() async {
        final payload = property.toInsert();
        final row = id == null
            ? await _db.from('properties').insert(payload).select().single()
            : await _db
                .from('properties')
                .update(payload)
                .eq('id', id)
                .select()
                .single();
        return Property.fromJson(row);
      });

  Future<Unit> upsertUnit(Unit unit, {String? id}) => _guard(() async {
        final payload = unit.toInsert();
        final row = id == null
            ? await _db.from('units').insert(payload).select().single()
            : await _db.from('units').update(payload).eq('id', id).select().single();
        return Unit.fromJson(row);
      });
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(supabaseProvider)),
);

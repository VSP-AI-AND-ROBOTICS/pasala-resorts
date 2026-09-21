import 'package:flutter_test/flutter_test.dart';
import 'package:resorthub/core/models/user_profile.dart';
import 'package:resorthub/core/services/mock_data_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Super Admin - Resort Admin Assignment Rules', () {
    final store = MockDataStore.instance;

    test('Assigning an admin updates their resortId association', () {
      final grandPalmsAdmin = store.getAssignedAdminForResort('resort-grand-palms');
      expect(grandPalmsAdmin, isNotNull);
      expect(grandPalmsAdmin!.email, equals('admin@grandpalms.com'));
      expect(grandPalmsAdmin.resortId, equals('resort-grand-palms'));
    });

    test('Admin assigned to one resort has resortId non-null and is identified as assigned', () {
      final admin = store.profiles['admin@grandpalms.com'];
      expect(admin, isNotNull);
      expect(admin!.role, equals(AppRole.admin));
      expect(admin.resortId, equals('resort-grand-palms'));
    });

    test('Super Admin can register a new admin and assign them directly to a resort', () {
      final newAdmin = store.createAndAssignAdmin(
        fullName: 'New Test Manager',
        email: 'newmanager@lakesideeco.com',
        resortId: 'resort-lakeside-eco',
      );

      expect(newAdmin.resortId, equals('resort-lakeside-eco'));
      expect(store.getAssignedAdminForResort('resort-lakeside-eco')?.email, equals('newmanager@lakesideeco.com'));
    });
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/models/room_status.dart';
import 'package:pasala/data/repositories/room_status_repository.dart';

import '../support/fake_room_board_source.dart';

void main() {
  test(
    'roomBoardProvider reads the board of the resort it is keyed by',
    () async {
      final source = FakeRoomBoardSource()
        ..entries = [boardEntry(unitId: 'u1')];
      final container = ProviderContainer(
        overrides: [roomBoardSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(roomBoardProvider('p1'), (_, _) {});
      addTearDown(sub.close);

      final rows = await container.read(roomBoardProvider('p1').future);

      expect(rows.single.unitId, 'u1');
      expect(source.boardCalls, ['p1']);
    },
  );

  test('dispatchableStaffProvider asks for the roster of the resort it is '
      'keyed by', () async {
    final source = FakeRoomBoardSource()
      ..staff = [
        const DispatchableStaff(userId: 's1', fullName: 'Hari Housekeeper'),
      ];
    final container = ProviderContainer(
      overrides: [roomBoardSourceProvider.overrideWithValue(source)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(dispatchableStaffProvider('p1'), (_, _) {});
    addTearDown(sub.close);

    final staff = await container.read(dispatchableStaffProvider('p1').future);

    expect(staff.single.userId, 's1');
    expect(source.staffCalls, ['p1']);
  });
}

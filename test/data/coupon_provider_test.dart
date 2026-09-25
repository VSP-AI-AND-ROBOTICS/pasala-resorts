import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pasala/data/repositories/coupon_repository.dart';

import '../support/fake_coupon_source.dart';

void main() {
  test(
    'couponsProvider lists the coupons of the resort it is keyed by',
    () async {
      final source = FakeCouponSource()..coupons = [couponRow(id: 'c1')];
      final container = ProviderContainer(
        overrides: [couponSourceProvider.overrideWithValue(source)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(couponsProvider('p1'), (_, _) {});
      addTearDown(sub.close);

      final rows = await container.read(couponsProvider('p1').future);

      expect(rows.single.id, 'c1');
      expect(source.listCalls, ['p1']);
    },
  );
}

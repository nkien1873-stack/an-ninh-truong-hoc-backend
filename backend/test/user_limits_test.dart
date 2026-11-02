import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  test('giới hạn theo tài khoản: quá số lần thì báo 429 tiếng Việt, hết thời gian thì được tiếp', () {
    final clock = TestClock(DateTime.utc(2026, 10, 28, 9));
    final limits = UserLimits(clock: clock.call);
    for (var i = 0; i < 10; i++) {
      limits.check(limits.reports, 'u1', 'gửi báo cáo');
    }
    expect(
      () => limits.check(limits.reports, 'u1', 'gửi báo cáo'),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 429)
          .having((e) => e.message, 'message', contains('gửi báo cáo quá nhiều lần'))),
    );
    // Tài khoản khác không bị ảnh hưởng.
    limits.check(limits.reports, 'u2', 'gửi báo cáo');
    clock.advance(const Duration(minutes: 11));
    limits.check(limits.reports, 'u1', 'gửi báo cáo');
  });
}

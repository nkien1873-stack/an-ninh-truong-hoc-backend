import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

void main() {
  test('client không giả được IP bằng cách tự gửi X-Forwarded-For', () {
    expect(proxiedClientIp({'x-forwarded-for': '1.1.1.1, 2.2.2.2'}), '2.2.2.2');
    expect(proxiedClientIp({'x-forwarded-for': '1.1.1.1, 2.2.2.2', 'cf-connecting-ip': '3.3.3.3'}), '3.3.3.3');
  });

  test('không có header proxy thì dùng địa chỉ kết nối', () {
    expect(proxiedClientIp({}), isNull);
    expect(proxiedClientIp({'x-forwarded-for': '  '}), isNull);
  });
}

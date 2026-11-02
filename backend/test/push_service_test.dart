import 'package:campus_safety_backend/src/notifications/push_service.dart';
import 'package:test/test.dart';

void main() {
  test('nhận ra token chết kể cả khi thư viện gộp lỗi thành internal-error', () {
    const internal = 'messaging/internal-error';
    expect(FcmPushService.isDeadToken(internal, 'DetailedApiRequestError(status: 404, message: NotRegistered)'), isTrue);
    expect(
      FcmPushService.isDeadToken(internal, 'DetailedApiRequestError(status: 400, message: The registration token is not a valid FCM registration token)'),
      isTrue,
    );
    expect(FcmPushService.isDeadToken('messaging/registration-token-not-registered', ''), isTrue);
  });

  test('lỗi tạm thời không làm mất token còn dùng được', () {
    expect(FcmPushService.isDeadToken('messaging/internal-error', 'DetailedApiRequestError(status: 503, message: Unavailable)'), isFalse);
  });
}

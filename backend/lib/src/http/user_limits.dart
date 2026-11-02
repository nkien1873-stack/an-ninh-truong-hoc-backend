import '../auth/ip_rate_limiter.dart';
import 'api_exception.dart';

/// Giới hạn tần suất theo tài khoản cho các thao tác ghi, chống spam báo cáo/ảnh/tin nhắn.
/// Lưu trong bộ nhớ tiến trình (mỗi backend một bộ đếm), đủ để chặn lạm dụng từ một máy.
class UserLimits {
  UserLimits({DateTime Function()? clock})
      : reports = SlidingWindowRateLimiter(maxEvents: 10, window: const Duration(minutes: 10), clock: clock),
        images = SlidingWindowRateLimiter(maxEvents: 30, window: const Duration(minutes: 10), clock: clock),
        comments = SlidingWindowRateLimiter(maxEvents: 30, window: const Duration(minutes: 10), clock: clock),
        walks = SlidingWindowRateLimiter(maxEvents: 10, window: const Duration(hours: 1), clock: clock),
        passwordChanges = SlidingWindowRateLimiter(maxEvents: 5, window: const Duration(minutes: 15), clock: clock),
        broadcasts = SlidingWindowRateLimiter(maxEvents: 10, window: const Duration(hours: 1), clock: clock);

  final SlidingWindowRateLimiter reports;
  final SlidingWindowRateLimiter images;
  final SlidingWindowRateLimiter comments;
  final SlidingWindowRateLimiter walks;
  final SlidingWindowRateLimiter passwordChanges;
  final SlidingWindowRateLimiter broadcasts;

  /// Ném 429 với thông báo tiếng Việt nếu [uid] vượt giới hạn của [limiter].
  void check(SlidingWindowRateLimiter limiter, String uid, String action) {
    final wait = limiter.hit(uid);
    if (wait != null) {
      throw ApiException.tooManyRequests(
        'Bạn $action quá nhiều lần trong thời gian ngắn. Thử lại sau ${humanizeWait(wait)}.',
        retryAfter: wait,
      );
    }
  }
}

/// Giới hạn số lần thao tác theo khoá (IP) trong cửa sổ trượt, lưu trong bộ nhớ tiến trình.
///
/// Đủ cho một instance backend. Khi chạy nhiều instance (Cloud Run scale), giới hạn theo số
/// email vẫn chính xác vì được lưu trong CSDL; giới hạn theo IP là lớp chặn bổ sung.
class SlidingWindowRateLimiter {
  SlidingWindowRateLimiter({
    required this.maxEvents,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int maxEvents;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, List<DateTime>> _events = {};

  /// Ghi nhận một lần thao tác. Trả về `null` nếu được phép, hoặc thời gian phải chờ.
  Duration? hit(String key) {
    final now = _clock();
    final list = _events.putIfAbsent(key, () => <DateTime>[])
      ..removeWhere((t) => now.difference(t) >= window);
    if (list.length >= maxEvents) {
      return window - now.difference(list.first);
    }
    list.add(now);
    if (_events.length > 10000) _evictOld(now);
    return null;
  }

  void _evictOld(DateTime now) {
    _events.removeWhere((_, list) {
      list.removeWhere((t) => now.difference(t) >= window);
      return list.isEmpty;
    });
  }
}

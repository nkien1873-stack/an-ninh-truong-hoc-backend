/// Chính sách OTP, dùng chung để app hiển thị đếm ngược đúng với backend.
abstract final class OtpPolicy {
  static const int codeLength = 6;
  static const Duration ttl = Duration(minutes: 5);
  static const int maxVerifyAttempts = 5;
  static const Duration resendCooldown = Duration(seconds: 60);
  static const int maxSendsPerHour = 5;
  static const int maxSendsPerDay = 10;

  static final RegExp codePattern = RegExp(r'^\d{6}$');

  /// Lỗi tiếng Việt cho mã OTP người dùng nhập, `null` nếu đúng định dạng.
  static String? validateCode(String? code) {
    final c = code?.trim() ?? '';
    if (c.isEmpty) return 'Nhập mã gồm $codeLength chữ số.';
    if (!codePattern.hasMatch(c)) return 'Mã OTP gồm đúng $codeLength chữ số.';
    return null;
  }
}

/// Giới hạn độ dài hồ sơ.
abstract final class ProfileLimits {
  static const int minNameLength = 2;
  static const int maxNameLength = 60;

  static String? validateDisplayName(String? name) {
    final n = name?.trim() ?? '';
    if (n.length < minNameLength) return 'Nhập họ tên (ít nhất $minNameLength ký tự).';
    if (n.length > maxNameLength) return 'Họ tên tối đa $maxNameLength ký tự.';
    return null;
  }
}

/// Quy tắc tên đăng nhập và mật khẩu, dùng chung để app báo lỗi giống hệt backend.
library;

abstract final class UsernamePolicy {
  static const minLength = 3;
  static const maxLength = 30;

  static final _pattern = RegExp(r'^[a-z][a-z0-9._]*$');

  /// Chuẩn hoá: bỏ khoảng trắng hai đầu, chữ thường.
  static String normalize(String input) => input.trim().toLowerCase();

  /// Lỗi tiếng Việt, hoặc `null` nếu hợp lệ.
  static String? validate(String? input) {
    final v = normalize(input ?? '');
    if (v.isEmpty) return 'Nhập tên đăng nhập.';
    if (v.length < minLength || v.length > maxLength) {
      return 'Tên đăng nhập dài $minLength đến $maxLength ký tự.';
    }
    if (!_pattern.hasMatch(v)) {
      return 'Tên đăng nhập bắt đầu bằng chữ cái, chỉ gồm chữ không dấu, số, dấu chấm hoặc gạch dưới.';
    }
    if (v.contains('..') || v.endsWith('.')) return 'Dấu chấm không được đứng liền nhau hoặc ở cuối.';
    return null;
  }
}

abstract final class PasswordPolicy {
  static const minLength = 8;
  static const maxLength = 64;

  /// Lỗi tiếng Việt, hoặc `null` nếu hợp lệ. Mật khẩu không bị chuẩn hoá (giữ nguyên khoảng trắng).
  static String? validate(String? input) {
    final v = input ?? '';
    if (v.isEmpty) return 'Nhập mật khẩu.';
    if (v.length < minLength) return 'Mật khẩu ít nhất $minLength ký tự.';
    if (v.length > maxLength) return 'Mật khẩu tối đa $maxLength ký tự.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Mật khẩu cần có cả chữ và số.';
    }
    return null;
  }
}

/// Mã số sinh viên: bắt buộc khi đăng ký là Sinh viên, mỗi MSSV chỉ một tài khoản.
abstract final class StudentIdPolicy {
  static const minLength = 6;
  static const maxLength = 12;

  static final _pattern = RegExp(r'^\d+$');

  static String normalize(String input) => input.replaceAll(RegExp(r'\s'), '');

  /// Lỗi tiếng Việt, hoặc `null` nếu hợp lệ.
  static String? validate(String? input) {
    final v = normalize(input ?? '');
    if (v.isEmpty) return 'Nhập mã số sinh viên (MSSV).';
    if (!_pattern.hasMatch(v)) return 'MSSV chỉ gồm chữ số.';
    if (v.length < minLength || v.length > maxLength) return 'MSSV dài $minLength đến $maxLength chữ số.';
    return null;
  }
}

/// Báo cáo sai sự thật: bảo vệ hoặc quản trị đánh dấu khi từ chối. Đủ [lockThreshold] lần thì
/// tài khoản người báo tự bị khoá (kể cả khi báo ẩn danh, backend vẫn biết ai gửi).
abstract final class FakeReportPolicy {
  static const lockThreshold = 3;

  /// Trạng thái khoá khi quản trị chỉnh tài khoản. Người báo có đủ [lockThreshold] cảnh báo thì
  /// luôn bị khoá; muốn mở khoá phải giảm số cảnh báo xuống dưới ngưỡng trước. [error] khác `null`
  /// khi quản trị muốn mở khoá mà chưa giảm cảnh báo.
  static ({bool locked, String? error}) resolveLock({
    required bool isReporter,
    required int warnings,
    required bool wantLocked,
  }) {
    if (isReporter && warnings >= lockThreshold) {
      return (
        locked: true,
        error: wantLocked
            ? null
            : 'Tài khoản đang có $lockThreshold cảnh báo nên không mở khoá được. '
                'Giảm số lần cảnh báo xuống dưới $lockThreshold trước.',
      );
    }
    return (locked: wantLocked, error: null);
  }
}

/// Giới hạn đăng nhập sai.
abstract final class LoginPolicy {
  static const maxFailures = 5;
  static const lockDuration = Duration(minutes: 15);
}

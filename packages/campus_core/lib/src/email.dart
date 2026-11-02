/// Chuẩn hoá và kiểm tra địa chỉ email dùng để đăng nhập (nhận OTP).
library;

enum EmailValidationError {
  empty('Vui lòng nhập email.'),
  tooLong('Email quá dài.'),
  invalid('Email không hợp lệ, ví dụ ten@gmail.com.');

  const EmailValidationError(this.message);

  /// Thông báo tiếng Việt hiển thị cho người dùng.
  final String message;
}

class EmailFormatException implements Exception {
  const EmailFormatException(this.error);

  final EmailValidationError error;

  String get message => error.message;

  @override
  String toString() => 'EmailFormatException(${error.name}): ${error.message}';
}

/// Email đã chuẩn hoá (bỏ khoảng trắng, chữ thường). Mỗi email là một tài khoản.
class EmailAddress {
  const EmailAddress._(this.value);

  static const maxLength = 254;

  static final _pattern = RegExp(
    // Không nhận "/" (email được dùng làm ID tài liệu Firestore `email_index/{email}`).
    r"^[a-z0-9.!#$%&'*+=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$",
  );

  /// Dạng chữ thường, ví dụ `ten@gmail.com`.
  final String value;

  /// Phần trước `@`.
  String get localPart => value.substring(0, value.indexOf('@'));

  /// Che bớt để ghi log và hiển thị: `ng***@gmail.com`.
  String get masked => maskEmail(value);

  /// Chuẩn hoá chuỗi người dùng nhập. Ném [EmailFormatException] nếu không hợp lệ.
  static EmailAddress parse(String input) {
    final v = input.trim().toLowerCase();
    if (v.isEmpty) throw const EmailFormatException(EmailValidationError.empty);
    if (v.length > maxLength) throw const EmailFormatException(EmailValidationError.tooLong);
    if (!_pattern.hasMatch(v) || v.contains('..')) {
      throw const EmailFormatException(EmailValidationError.invalid);
    }
    return EmailAddress._(v);
  }

  /// Giống [parse] nhưng trả về `null` thay vì ném lỗi.
  static EmailAddress? tryParse(String? input) {
    if (input == null) return null;
    try {
      return parse(input);
    } on EmailFormatException {
      return null;
    }
  }

  /// Trả về thông báo lỗi tiếng Việt, hoặc `null` nếu hợp lệ. Dùng cho validator của form.
  static String? validate(String? input) {
    try {
      parse(input ?? '');
      return null;
    } on EmailFormatException catch (e) {
      return e.message;
    }
  }

  @override
  bool operator ==(Object other) => other is EmailAddress && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// Giữ 2 ký tự đầu của phần tên và toàn bộ tên miền: `nguyen@gmail.com` thành `ng***@gmail.com`.
String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return '***';
  final name = email.substring(0, at);
  final keep = name.length <= 2 ? name.substring(0, 1) : name.substring(0, 2);
  return '$keep***${email.substring(at)}';
}

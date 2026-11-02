/// Chuẩn hoá và kiểm tra số điện thoại di động Việt Nam.
///
/// Lưu ở dạng có mã quốc gia, ví dụ
/// `0987654321` phải gửi thành `84987654321`.
library;

/// Đầu số di động Việt Nam hợp lệ (2 chữ số ngay sau mã quốc gia 84),
/// theo kế hoạch chuyển đổi thuê bao 11 số sang 10 số năm 2018.
const Set<String> vietnamMobilePrefixes = {
  // Viettel
  '32', '33', '34', '35', '36', '37', '38', '39', '86', '96', '97', '98',
  // Vinaphone
  '81', '82', '83', '84', '85', '88', '91', '94',
  // MobiFone
  '70', '76', '77', '78', '79', '89', '90', '93',
  // Vietnamobile, Gmobile, Itel, Reddi, Wintel
  '52', '55', '56', '58', '59', '87', '92', '99',
};

enum PhoneValidationError {
  empty('Vui lòng nhập số điện thoại.'),
  invalidCharacters('Số điện thoại chỉ được chứa chữ số.'),
  wrongLength('Số điện thoại di động Việt Nam gồm 10 chữ số, ví dụ 0912 345 678.'),
  notVietnam('Chỉ hỗ trợ số điện thoại Việt Nam (+84).'),
  unknownPrefix('Đầu số này không phải số di động Việt Nam.');

  const PhoneValidationError(this.message);

  /// Thông báo tiếng Việt hiển thị cho người dùng.
  final String message;
}

class PhoneFormatException implements Exception {
  const PhoneFormatException(this.error);

  final PhoneValidationError error;

  String get message => error.message;

  @override
  String toString() => 'PhoneFormatException(${error.name}): ${error.message}';
}

/// Số di động Việt Nam đã chuẩn hoá. [international] luôn có dạng `84xxxxxxxxx`.
class VietnamPhone {
  const VietnamPhone._(this.international);

  /// Dạng `84xxxxxxxxx` (11 chữ số), dùng để lưu trữ.
  final String international;

  /// Dạng nội địa `0xxxxxxxxx`.
  String get local => '0${international.substring(2)}';

  /// Dạng E.164 có dấu cộng `+84xxxxxxxxx`.
  String get e164 => '+$international';

  /// Dạng hiển thị dễ đọc `0912 345 678`.
  String get display {
    final l = local;
    return '${l.substring(0, 4)} ${l.substring(4, 7)} ${l.substring(7)}';
  }

  /// Che bớt số để ghi log: `84912***678`.
  String get masked => maskPhone(international);

  /// Chuẩn hoá chuỗi người dùng nhập. Ném [PhoneFormatException] nếu không hợp lệ.
  ///
  /// Chấp nhận: `0912345678`, `0912 345 678`, `0912.345.678`, `84912345678`,
  /// `+84 912 345 678`, `0084912345678`, `(+84) 912-345-678`.
  static VietnamPhone parse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const PhoneFormatException(PhoneValidationError.empty);
    }
    final compact = trimmed.replaceAll(RegExp(r'[\s.\-()]'), '');
    final hasPlus = compact.startsWith('+');
    final digits = hasPlus ? compact.substring(1) : compact;
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) {
      throw const PhoneFormatException(PhoneValidationError.invalidCharacters);
    }

    String national;
    if (hasPlus) {
      if (!digits.startsWith('84')) {
        throw const PhoneFormatException(PhoneValidationError.notVietnam);
      }
      national = digits.substring(2);
    } else if (digits.startsWith('0084')) {
      national = digits.substring(4);
    } else if (digits.startsWith('84') && digits.length == 11) {
      national = digits.substring(2);
    } else if (digits.startsWith('0')) {
      national = digits.substring(1);
    } else if (digits.length == 9) {
      // Người dùng bỏ số 0 đầu (thường gặp khi dán từ Excel).
      national = digits;
    } else if (digits.startsWith('00')) {
      throw const PhoneFormatException(PhoneValidationError.notVietnam);
    } else {
      throw const PhoneFormatException(PhoneValidationError.wrongLength);
    }

    if (national.startsWith('0')) {
      // Trường hợp +840912... : bỏ số 0 thừa sau mã quốc gia.
      national = national.substring(1);
    }
    if (national.length != 9) {
      throw const PhoneFormatException(PhoneValidationError.wrongLength);
    }
    if (!vietnamMobilePrefixes.contains(national.substring(0, 2))) {
      throw const PhoneFormatException(PhoneValidationError.unknownPrefix);
    }
    return VietnamPhone._('84$national');
  }

  /// Giống [parse] nhưng trả về `null` thay vì ném lỗi.
  static VietnamPhone? tryParse(String? input) {
    if (input == null) return null;
    try {
      return parse(input);
    } on PhoneFormatException {
      return null;
    }
  }

  /// Trả về thông báo lỗi tiếng Việt, hoặc `null` nếu hợp lệ. Dùng cho validator của form.
  static String? validate(String? input) {
    try {
      parse(input ?? '');
      return null;
    } on PhoneFormatException catch (e) {
      return e.message;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is VietnamPhone && other.international == international;

  @override
  int get hashCode => international.hashCode;

  @override
  String toString() => international;
}

/// Che phần giữa số điện thoại, giữ 5 ký tự đầu và 3 ký tự cuối.
/// `84912345678` thành `84912***678`. Chuỗi quá ngắn được che toàn bộ.
String maskPhone(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 9) return '***';
  return '${digits.substring(0, 5)}***${digits.substring(digits.length - 3)}';
}

import 'package:campus_core/campus_core.dart';
import 'package:test/test.dart';

void main() {
  group('VietnamPhone.parse chuẩn hoá về 84xxxxxxxxx', () {
    const expected = '84912345678';
    for (final input in [
      '0912345678',
      '0912 345 678',
      '0912.345.678',
      '0912-345-678',
      '84912345678',
      '+84912345678',
      '+84 912 345 678',
      '(+84) 912-345-678',
      '0084912345678',
      '912345678',
      '+840912345678',
      '  0912345678  ',
    ]) {
      test('"$input"', () {
        expect(VietnamPhone.parse(input).international, expected);
      });
    }

    test('các dạng hiển thị', () {
      final p = VietnamPhone.parse('0912345678');
      expect(p.local, '0912345678');
      expect(p.e164, '+84912345678');
      expect(p.display, '0912 345 678');
      expect(p.masked, '84912***678');
    });

    test('đầu số của các nhà mạng', () {
      for (final n in ['0321234567', '0861234567', '0771234567', '0561234567', '0991234567']) {
        expect(VietnamPhone.tryParse(n), isNotNull, reason: n);
      }
    });
  });

  group('VietnamPhone.parse từ chối số sai', () {
    void expectError(String input, PhoneValidationError error) {
      expect(
        () => VietnamPhone.parse(input),
        throwsA(isA<PhoneFormatException>().having((e) => e.error, 'error', error)),
        reason: input,
      );
    }

    test('rỗng', () => expectError('   ', PhoneValidationError.empty));
    test('có chữ cái', () => expectError('09123abc78', PhoneValidationError.invalidCharacters));
    test('thiếu số', () => expectError('091234567', PhoneValidationError.wrongLength));
    test('thừa số', () => expectError('09123456789', PhoneValidationError.wrongLength));
    test('số nước ngoài', () => expectError('+6591234567', PhoneValidationError.notVietnam));
    test('số cố định Hà Nội', () => expectError('02412345678', PhoneValidationError.wrongLength));
    test('đầu số không tồn tại', () => expectError('0112345678', PhoneValidationError.unknownPrefix));
    test('đầu số 80 không phải di động', () => expectError('0801234567', PhoneValidationError.unknownPrefix));
  });

  test('validate trả về thông báo tiếng Việt', () {
    expect(VietnamPhone.validate('0912345678'), isNull);
    expect(VietnamPhone.validate(''), 'Vui lòng nhập số điện thoại.');
    expect(VietnamPhone.validate(null), isNotNull);
  });

  test('so sánh bằng theo số đã chuẩn hoá', () {
    expect(VietnamPhone.parse('0912345678'), VietnamPhone.parse('+84 912 345 678'));
  });

  test('maskPhone', () {
    expect(maskPhone('84912345678'), '84912***678');
    expect(maskPhone('0912345678'), '09123***678');
    expect(maskPhone('123'), '***');
  });
}

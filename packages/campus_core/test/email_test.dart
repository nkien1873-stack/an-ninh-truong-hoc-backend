import 'package:campus_core/campus_core.dart';
import 'package:test/test.dart';

void main() {
  test('chuẩn hoá: bỏ khoảng trắng, chữ thường', () {
    expect(EmailAddress.parse('  Nguyen.Van.A@Gmail.COM ').value, 'nguyen.van.a@gmail.com');
    expect(EmailAddress.parse('a+test@sv.hcmus.edu.vn').value, 'a+test@sv.hcmus.edu.vn');
  });

  test('email không hợp lệ báo lỗi tiếng Việt', () {
    expect(EmailAddress.validate(''), EmailValidationError.empty.message);
    for (final bad in ['abc', 'abc@', '@gmail.com', 'a@gmail', 'a b@gmail.com', 'a..b@gmail.com', 'a@-x.com', 'a/b@gmail.com']) {
      expect(EmailAddress.validate(bad), EmailValidationError.invalid.message, reason: bad);
    }
    expect(EmailAddress.tryParse('abc'), isNull);
  });

  test('so sánh theo dạng đã chuẩn hoá', () {
    expect(EmailAddress.parse('A@B.com'), EmailAddress.parse('a@b.com'));
  });

  test('che email', () {
    expect(EmailAddress.parse('nguyen@gmail.com').masked, 'ng***@gmail.com');
    expect(EmailAddress.parse('ab@gmail.com').masked, 'a***@gmail.com');
    expect(maskEmail('khong-phai-email'), '***');
  });
}

import 'dart:convert';

import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  const url = 'https://script.google.com/macros/s/abc/exec';
  final to = EmailAddress.parse('khoa@gmail.com');
  const ttl = Duration(minutes: 5);

  AppsScriptOtpMailer mailer(MockClientHandler handler) => AppsScriptOtpMailer(
        url: url,
        secret: 's3cret',
        fromName: 'An ninh',
        appName: 'An ninh',
        client: MockClient(handler),
      );

  http.Response json(Object body) => http.Response(jsonEncode(body), 200);

  test('gửi kèm secret và mã, theo chuyển hướng của Apps Script để đọc kết quả', () async {
    final seen = <http.BaseRequest>[];
    await mailer((req) async {
      seen.add(req);
      if (req.method == 'POST') {
        return http.Response('', 302, headers: {'location': 'https://script.googleusercontent.com/kq'});
      }
      return json({'ok': true});
    }).sendOtp(to, '123456', ttl: ttl);

    final body = jsonDecode((seen.first as http.Request).body) as Map<String, dynamic>;
    expect(seen.first.url.toString(), url);
    expect(body['secret'], 's3cret');
    expect(body['to'], 'khoa@gmail.com');
    expect(body['subject'], contains('123456'));
    expect(body['html'], contains('123456'));
    expect(seen.last.method, 'GET');
  });

  test('script báo sai secret: lỗi rõ cho quản trị', () async {
    await expectLater(
      mailer((_) async => json({'ok': false, 'error': 'unauthorized'})).sendOtp(to, '1', ttl: ttl),
      throwsA(isA<OtpMailException>().having((e) => e.message, 'message', contains('MAIL_SCRIPT_SECRET'))),
    );
  });

  test('script trả trang HTML (chưa mở quyền truy cập) không bị coi là đã gửi', () async {
    await expectLater(
      mailer((_) async => http.Response('<html>Sign in</html>', 200)).sendOtp(to, '1', ttl: ttl),
      throwsA(isA<OtpMailException>()),
    );
  });

  test('mất mạng: báo lỗi kết nối', () async {
    await expectLater(
      mailer((_) async => throw http.ClientException('down')).sendOtp(to, '1', ttl: ttl),
      throwsA(isA<OtpMailException>().having((e) => e.message, 'message', contains('Không kết nối'))),
    );
  });

  group('cấu hình', () {
    final base = {'MONGODB_URI': 'mongodb://localhost/x', 'FIREBASE_PROJECT_ID': 'p', 'OTP_PEPPER': 'x' * 32};

    test('có MAIL_SCRIPT_URL thì không cần SMTP', () {
      final config = AppConfig.fromEnvironment({...base, 'MAIL_SCRIPT_URL': url, 'MAIL_SCRIPT_SECRET': 'y' * 32});
      expect(config.mailScriptUrl, url);
    });

    test('secret ngắn bị từ chối; không có script thì vẫn bắt buộc SMTP', () {
      expect(
        () => AppConfig.fromEnvironment({...base, 'MAIL_SCRIPT_URL': url, 'MAIL_SCRIPT_SECRET': 'ngan'}),
        throwsA(isA<ConfigException>()),
      );
      expect(() => AppConfig.fromEnvironment(base), throwsA(isA<ConfigException>()));
    });
  });
}

import 'dart:convert';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

void main() {
  Request request(String body, {Map<String, String> headers = const {}}) =>
      Request.post(Uri.parse('http://x/a'), body: body, headers: headers);

  test('đọc body tiếng Việt đúng', () async {
    expect(await readBody(request('Tiếng Việt'), maxBytes: 100), 'Tiếng Việt');
  });

  test('vượt giới hạn thì từ chối, kể cả khi không khai Content-Length', () async {
    final tooLarge = throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 413));
    await expectLater(readBody(request('x' * 101), maxBytes: 100), tooLarge);
    final declared = Request.post(Uri.parse('http://x/a'), body: Stream.value(utf8.encode('x')), headers: {'content-length': '999999'});
    await expectLater(readBody(declared, maxBytes: 100), tooLarge);
  });

  test('byte không phải UTF-8 báo lỗi 400', () async {
    final bad = Request.post(Uri.parse('http://x/a'), body: Stream.value(utf8.encode('a')..[0] = 0xFF));
    await expectLater(readBody(bad, maxBytes: 100), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)));
  });
}

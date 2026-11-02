import 'dart:convert';
import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

class _MemoryImages implements ImageRepository {
  final items = <String, (String, Uint8List)>{};

  @override
  Future<void> save(String id, {required String uploaderUid, required Uint8List bytes}) async =>
      items[id] = (uploaderUid, bytes);

  @override
  Future<Uint8List?> load(String id) async => items[id]?.$2;
}

void main() {
  late _MemoryImages store;
  late ImageService service;
  late UserRecord user;

  setUp(() {
    store = _MemoryImages();
    service = ImageService(store);
    user = MemoryUserRepository().seed(name: 'Trần Minh Khoa');
  });

  Uint8List jpeg(int size) => Uint8List(size)..setAll(0, [0xFF, 0xD8, 0xFF, 0xE0]);

  TypeMatcher<ApiException> invalid(String text) => isA<ApiException>()
      .having((e) => e.code, 'code', 'validation_failed')
      .having((e) => e.message, 'message', contains(text));

  test('lưu ảnh JPEG, trả đường dẫn hợp lệ cho báo cáo, đọc lại được', () async {
    final bytes = jpeg(2048);
    final path = await service.upload(user, base64Encode(bytes));
    expect(ReportLimits.imagePathPattern.hasMatch(path), isTrue, reason: path);
    final id = path.substring('report_images/'.length, path.length - 4);
    expect(id, hasLength(32));
    expect(store.items[id]!.$1, user.uid);
    expect(await service.load(id), bytes);
  });

  test('từ chối ảnh quá 700 KB, không phải JPEG, hoặc base64 lỗi', () async {
    await expectLater(service.upload(user, base64Encode(jpeg(ReportLimits.maxStoredImageBytes + 1))), throwsA(invalid('quá lớn')));
    await expectLater(service.upload(user, base64Encode(utf8.encode('<html>'))), throwsA(invalid('JPEG')));
    await expectLater(service.upload(user, '%%%'), throwsA(invalid('không hợp lệ')));
    expect(store.items, isEmpty);
  });

  test('ID sai định dạng không đọc kho', () async {
    expect(await service.load('../users/abc'), isNull);
  });
}

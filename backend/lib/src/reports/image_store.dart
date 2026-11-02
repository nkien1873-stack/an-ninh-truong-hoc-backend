import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:campus_core/campus_core.dart';
import 'package:mongo_dart/mongo_dart.dart' show BsonBinary, where;

import '../data/models.dart';
import '../data/mongo_store.dart';
import '../http/api_exception.dart';

/// Kho ảnh sự cố, lưu trong MongoDB (collection `report_images`).
abstract interface class ImageRepository {
  Future<void> save(String id, {required String uploaderUid, required Uint8List bytes});

  Future<Uint8List?> load(String id);
}

class MongoImageRepository implements ImageRepository {
  MongoImageRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.reportImages;

  @override
  Future<void> save(String id, {required String uploaderUid, required Uint8List bytes}) async {
    final result = await _store.run(
      _name,
      (c) => c.insertOne({
        '_id': id,
        'data': BsonBinary.from(bytes),
        'contentType': 'image/jpeg',
        'size': bytes.length,
        'uploaderUid': uploaderUid,
        'createdAt': DateTime.now().toUtc(),
      }),
    );
    if (!result.isSuccess) throw StateError('insert_image_failed');
  }

  @override
  Future<Uint8List?> load(String id) async {
    final data = (await _store.run(_name, (c) => c.findOne(where.eq('_id', id))))?['data'];
    return data is BsonBinary ? data.byteList : null;
  }
}

/// Nhận ảnh JPEG đã nén từ app, trả về đường dẫn `report_images/<id>.jpg` để gắn vào báo cáo.
///
/// ID ngẫu nhiên 32 ký tự (không đoán được) nên link xem ảnh `GET /images/<id>` không cần đăng nhập,
/// giống link tải có token của Firebase Storage; chỉ người xem được báo cáo mới biết link.
class ImageService {
  ImageService(this._images, {Random? random}) : _random = random ?? Random.secure();

  final ImageRepository _images;
  final Random _random;

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final idPattern = RegExp(r'^[A-Za-z0-9]{32}$');

  Future<String> upload(UserRecord user, String base64Data) async {
    final Uint8List bytes;
    try {
      bytes = base64Decode(base64Data.trim());
    } on FormatException {
      throw ApiException.validation({'image': 'Dữ liệu ảnh không hợp lệ.'});
    }
    if (bytes.isEmpty) throw ApiException.validation({'image': 'Ảnh trống.'});
    if (bytes.length > ReportLimits.maxStoredImageBytes) {
      throw ApiException.validation({'image': 'Ảnh quá lớn (tối đa 700 KB sau khi nén). Hãy chọn ảnh khác.'});
    }
    // JPEG bắt đầu bằng FF D8 FF.
    if (bytes.length < 3 || bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) {
      throw ApiException.validation({'image': 'Chỉ nhận ảnh JPEG.'});
    }
    final id = List.generate(32, (_) => _alphabet[_random.nextInt(_alphabet.length)]).join();
    await _images.save(id, uploaderUid: user.uid, bytes: bytes);
    return 'report_images/$id.jpg';
  }

  Future<Uint8List?> load(String id) => idPattern.hasMatch(id) ? _images.load(id) : Future.value();
}

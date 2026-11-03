import 'dart:async';
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart' show ConnectionException, Db, DbCollection, WriteResult;

/// Tên collection trong MongoDB.
abstract final class Collections {
  static const users = 'users';
  static const credentials = 'credentials';
  static const reports = 'reports';
  static const config = 'config';
  static const otp = 'otp_challenges';
  static const broadcasts = 'broadcasts';
  static const walks = 'walks';
  static const reportImages = 'report_images';
}

/// Kết nối MongoDB dùng chung. Tự kết nối lại khi Atlas đóng kết nối nhàn rỗi hoặc đổi máy chủ chính.
class MongoStore {
  MongoStore._(this._uri);

  final String _uri;
  Db? _db;
  Future<Db>? _opening;
  Timer? _heartbeat;

  /// Mã lỗi trùng khoá của MongoDB.
  static const duplicateKey = 11000;

  static bool isDuplicate(WriteResult result) => result.writeError?.code == duplicateKey;

  /// Atlas khai báo `authSource` trong bản ghi DNS, thư viện không đọc nên phải ghi rõ.
  /// `safeAtlas` để Atlas không ngắt kết nối khi có nhiều lệnh chạy song song.
  static String normalizeUri(String uri) {
    final extra = [
      if (!uri.contains('authSource=')) 'authSource=admin',
      if (!uri.contains('safeAtlas=')) 'safeAtlas=true',
    ];
    return extra.isEmpty ? uri : '$uri${uri.contains('?') ? '&' : '?'}${extra.join('&')}';
  }

  static Future<MongoStore> connect(String uri) async {
    final store = MongoStore._(normalizeUri(uri));
    await store._database();
    await store._ensureIndexes();
    store._heartbeat = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(store._ping()));
    return store;
  }

  Future<Db> _database() async {
    final db = _db;
    if (db != null && db.isConnected) return db;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Db> _open() async {
    await _discard();
    final db = await Db.create(_uri);
    await db.open(secure: true).timeout(const Duration(seconds: 30));
    return _db = db;
  }

  Future<void> _discard() async {
    final db = _db;
    _db = null;
    try {
      await db?.close();
    } on Object {
      // Kết nối đã hỏng sẵn.
    }
  }

  /// Phát hiện kết nối chết trước khi một request của người dùng gặp phải.
  Future<void> _ping() async {
    try {
      await (await _database()).pingCommand();
    } on Object catch (e) {
      stderr.writeln('[mongo] Mất kết nối: ${_safe(e)}');
      await _discard();
    }
  }

  /// Cơ sở dữ liệu có trả lời không (trang /health). Lỗi thì đóng kết nối để lần sau mở lại.
  Future<bool> isHealthy() async {
    try {
      await (await _database()).pingCommand().timeout(const Duration(seconds: 5));
      return true;
    } on Object catch (e) {
      stderr.writeln('[mongo] Kiểm tra sức khoẻ thất bại: ${_safe(e)}');
      await _discard();
      return false;
    }
  }

  /// Chạy [operation]; mất kết nối thì mở lại và thử thêm một lần.
  Future<T> run<T>(String collection, Future<T> Function(DbCollection c) operation) async {
    try {
      return await operation((await _database()).collection(collection));
    } on Object catch (e) {
      if (!_isConnectionError(e)) rethrow;
      stderr.writeln('[mongo] Thử kết nối lại: ${_safe(e)}');
      await _discard();
      return operation((await _database()).collection(collection));
    }
  }

  static bool _isConnectionError(Object e) {
    if (e is ConnectionException || e is SocketException) return true;
    final text = '$e'.toLowerCase();
    return text.contains('no master connection') || text.contains('connection closed');
  }

  /// Thông báo lỗi có thể chứa chuỗi kết nối kèm mật khẩu.
  static String _safe(Object e) => '$e'.replaceAll(RegExp(r'mongodb(\+srv)?://\S+'), '<uri>');

  Future<void> _ensureIndexes() async {
    Future<void> index(String collection, Map<String, Object> keys, {bool unique = false, Map<String, Object>? partial}) =>
        run(collection, (c) => c.createIndex(keys: keys, unique: unique, partialFilterExpression: partial));

    await index(Collections.users, {'email': 1}, unique: true);
    // Mỗi MSSV một tài khoản; tài khoản không có MSSV (giảng viên, bảo vệ) không tính.
    await index(
      Collections.users,
      {'studentId': 1},
      unique: true,
      partial: {
        'studentId': {r'$type': 'string'},
      },
    );
    await index(Collections.users, {'role': 1});
    await index(Collections.credentials, {'username': 1}, unique: true);
    await index(Collections.reports, {'createdAt': -1});
    await index(Collections.reports, {'status': 1, 'createdAt': -1});
    await index(Collections.reports, {'assigneeUid': 1, 'createdAt': -1});
    await index(Collections.reports, {'reporter.uid': 1, 'createdAt': -1});
    await index(Collections.walks, {'uid': 1, 'status': 1});
    await index(Collections.walks, {'status': 1});
    await index(Collections.broadcasts, {'createdAt': -1});
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    await _discard();
  }
}

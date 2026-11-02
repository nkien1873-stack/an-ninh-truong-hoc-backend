import 'package:campus_core/campus_core.dart';

import '../data/models.dart';
import '../http/api_exception.dart';
import '../notifications/notification_service.dart';
import '../notifications/push_service.dart';

/// Mức độ của cảnh báo toàn trường, quyết định màu banner và kênh push.
enum BroadcastLevel {
  info('info', 'Thông báo'),
  warning('warning', 'Cảnh báo'),
  danger('danger', 'Nguy hiểm');

  const BroadcastLevel(this.wire, this.label);

  final String wire;
  final String label;

  static BroadcastLevel? tryFromWire(String? wire) => values.where((v) => v.wire == wire).firstOrNull;
}

/// Cảnh báo toàn trường (`broadcasts/{id}`), mọi tài khoản đang hoạt động đọc được.
class BroadcastRecord {
  const BroadcastRecord({
    required this.id,
    required this.title,
    required this.body,
    required this.level,
    required this.createdAt,
    required this.expiresAt,
    required this.createdByUid,
    required this.createdByName,
    this.active = true,
    this.endedAt,
  });

  final String id;
  final String title;
  final String body;
  final BroadcastLevel level;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String createdByUid;
  final String createdByName;
  final bool active;
  final DateTime? endedAt;

  Map<String, Object?> toApiJson() => {
        'id': id,
        'title': title,
        'body': body,
        'level': level.wire,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'active': active,
        'createdByName': createdByName,
      };
}

abstract interface class BroadcastRepository {
  String newId();

  Future<void> create(BroadcastRecord record);

  Future<BroadcastRecord?> byId(String id);

  Future<void> end(String id, DateTime at);

  /// Cảnh báo gần nhất (kể cả đã gỡ), mới nhất trước.
  Future<List<BroadcastRecord>> recent({required int limit});
}

/// Giới hạn nội dung cảnh báo.
abstract final class BroadcastLimits {
  static const maxTitle = 80;
  static const maxBody = 500;
  static const minHours = 1;
  static const maxHours = 72;
}

class BroadcastService {
  BroadcastService({
    required BroadcastRepository broadcasts,
    required NotificationService notifications,
    DateTime Function()? clock,
  })  : _broadcasts = broadcasts,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final BroadcastRepository _broadcasts;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  /// Cảnh báo gần nhất để app hiện banner và lịch sử.
  Future<List<BroadcastRecord>> recent() => _broadcasts.recent(limit: 20);

  /// Quản trị gửi cảnh báo: lưu CSDL (banner trong app) và push tới mọi tài khoản.
  /// Trả về (cảnh báo, số thiết bị nhận push).
  Future<(BroadcastRecord, int)> send(
    UserRecord admin, {
    required String title,
    required String body,
    required BroadcastLevel level,
    int hours = 12,
  }) async {
    if (admin.role != UserRole.admin) throw ApiException.forbidden();
    final t = title.trim();
    final b = body.trim();
    final errors = <String, String>{
      if (t.length < 3) 'title': 'Nhập tiêu đề (ít nhất 3 ký tự).',
      if (t.length > BroadcastLimits.maxTitle) 'title': 'Tiêu đề tối đa ${BroadcastLimits.maxTitle} ký tự.',
      if (b.length < 3) 'body': 'Nhập nội dung (ít nhất 3 ký tự).',
      if (b.length > BroadcastLimits.maxBody) 'body': 'Nội dung tối đa ${BroadcastLimits.maxBody} ký tự.',
      if (hours < BroadcastLimits.minHours || hours > BroadcastLimits.maxHours)
        'hours': 'Thời gian hiển thị từ ${BroadcastLimits.minHours} đến ${BroadcastLimits.maxHours} giờ.',
    };
    if (errors.isNotEmpty) throw ApiException.validation(errors);

    final now = _clock().toUtc();
    final record = BroadcastRecord(
      id: _broadcasts.newId(),
      title: t,
      body: b,
      level: level,
      createdAt: now,
      expiresAt: now.add(Duration(hours: hours)),
      createdByUid: admin.uid,
      createdByName: admin.greetingName,
    );
    await _broadcasts.create(record);
    final delivered = await _notifications.pushToAll(PushMessage(
      title: '${level.label}: $t',
      body: b,
      data: {'type': 'broadcast', 'broadcastId': record.id},
      urgent: level != BroadcastLevel.info,
    ));
    return (record, delivered);
  }

  Future<void> end(UserRecord admin, String id) async {
    if (admin.role != UserRole.admin) throw ApiException.forbidden();
    if (await _broadcasts.byId(id) == null) throw ApiException.notFound('Không tìm thấy cảnh báo.');
    await _broadcasts.end(id, _clock().toUtc());
  }
}

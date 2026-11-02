import 'dart:async';
import 'dart:io';

import 'package:campus_core/campus_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import '../http/api_exception.dart';
import '../notifications/notification_service.dart';
import '../notifications/push_service.dart';
import '../reports/report_service.dart';

enum WalkStatus {
  active('active', 'Đang đi'),
  arrived('arrived', 'Đã tới nơi'),
  cancelled('cancelled', 'Đã huỷ'),
  overdue('overdue', 'Quá giờ, đã báo bảo vệ'),
  sos('sos', 'Đã bấm khẩn cấp');

  const WalkStatus(this.wire, this.label);

  final String wire;
  final String label;

  static WalkStatus fromWire(String? wire) =>
      values.where((v) => v.wire == wire).firstOrNull ?? WalkStatus.cancelled;
}

/// Một lượt "Đi cùng tôi" (`walks/{id}`): người dùng hẹn giờ tới nơi; quá giờ chưa xác nhận
/// thì backend tự tạo báo cáo khẩn cấp kèm vị trí cuối cùng để bảo vệ trực xử lý.
class WalkRecord {
  const WalkRecord({
    required this.id,
    required this.uid,
    required this.displayName,
    required this.destination,
    required this.startedAt,
    required this.dueAt,
    required this.status,
    required this.updatedAt,
    this.phone,
    this.lastLatitude,
    this.lastLongitude,
    this.lastAccuracy,
    this.lastLocationAt,
    this.reportId,
    this.endedAt,
  });

  final String id;
  final String uid;
  final String displayName;

  /// Số liên hệ dạng `0xxxxxxxxx` để bảo vệ gọi, có thể trống.
  final String? phone;
  final String destination;
  final DateTime startedAt;
  final DateTime dueAt;
  final WalkStatus status;
  final DateTime updatedAt;
  final double? lastLatitude;
  final double? lastLongitude;
  final double? lastAccuracy;
  final DateTime? lastLocationAt;

  /// Báo cáo khẩn cấp được tạo khi quá giờ hoặc bấm khẩn cấp.
  final String? reportId;
  final DateTime? endedAt;

  bool get isActive => status == WalkStatus.active;

  bool get hasLocation => lastLatitude != null && lastLongitude != null;

  WalkRecord copyWith({
    DateTime? dueAt,
    WalkStatus? status,
    DateTime? updatedAt,
    double? lastLatitude,
    double? lastLongitude,
    double? lastAccuracy,
    DateTime? lastLocationAt,
    String? reportId,
    DateTime? endedAt,
  }) =>
      WalkRecord(
        id: id,
        uid: uid,
        displayName: displayName,
        phone: phone,
        destination: destination,
        startedAt: startedAt,
        dueAt: dueAt ?? this.dueAt,
        status: status ?? this.status,
        updatedAt: updatedAt ?? this.updatedAt,
        lastLatitude: lastLatitude ?? this.lastLatitude,
        lastLongitude: lastLongitude ?? this.lastLongitude,
        lastAccuracy: lastAccuracy ?? this.lastAccuracy,
        lastLocationAt: lastLocationAt ?? this.lastLocationAt,
        reportId: reportId ?? this.reportId,
        endedAt: endedAt ?? this.endedAt,
      );

  Map<String, Object?> toApiJson() => {
        'id': id,
        'destination': destination,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'dueAt': dueAt.toUtc().toIso8601String(),
        'status': status.wire,
        'reportId': reportId,
      };

  /// Đầy đủ thông tin cho chính chủ và bảo vệ, quản trị.
  Map<String, Object?> toDetailJson() => {
        ...toApiJson(),
        'uid': uid,
        'displayName': displayName,
        'phone': phone,
        'lastLatitude': lastLatitude,
        'lastLongitude': lastLongitude,
        'lastLocationAt': lastLocationAt?.toUtc().toIso8601String(),
      };
}

abstract interface class WalkRepository {
  String newId();

  Future<WalkRecord?> byId(String id);

  /// Lượt đang đi của người dùng (mỗi người tối đa một lượt).
  Future<WalkRecord?> activeFor(String uid);

  Future<List<WalkRecord>> listActive();

  /// Ghi đè toàn bộ tài liệu (tạo lượt mới, gắn mã báo cáo vào lượt đã kết thúc).
  Future<void> save(WalkRecord walk);

  /// Đọc và ghi nguyên tử (khoá lạc quan) khi lượt **còn đang đi**. Trả về bản mới, hoặc `null` nếu
  /// lượt đã kết thúc (người dùng vừa bấm tới nơi, hoặc một backend khác vừa xử lý quá giờ).
  /// [update] có thể ném lỗi để huỷ thay đổi.
  ///
  /// Có thể có nhiều backend cùng chạy trên một CSDL nên mọi thay đổi trạng thái
  /// phải đi qua đây: chỉ một backend "giành" được lượt quá giờ và tạo báo cáo khẩn cấp.
  Future<WalkRecord?> updateIfActive(String id, WalkRecord Function(WalkRecord current) update);
}

abstract final class WalkLimits {
  static const minMinutes = 5;
  static const maxMinutes = 120;
  static const maxExtendMinutes = 30;

  /// Tổng thời gian một lượt (kể cả gia hạn).
  static const maxTotal = Duration(hours: 3);
  static const maxDestinationLength = 80;
}

class WalkService {
  WalkService({
    required WalkRepository walks,
    required UserRepository users,
    required ReportService reports,
    required NotificationService notifications,
    DateTime Function()? clock,
  })  : _walks = walks,
        _users = users,
        _reports = reports,
        _notifications = notifications,
        _clock = clock ?? DateTime.now;

  final WalkRepository _walks;
  final UserRepository _users;
  final ReportService _reports;
  final NotificationService _notifications;
  final DateTime Function() _clock;
  Timer? _timer;
  bool _checking = false;

  Future<WalkRecord?> activeFor(String uid) => _walks.activeFor(uid);

  Future<List<WalkRecord>> listActive() => _walks.listActive();

  Future<WalkRecord> start(
    UserRecord user, {
    required String destination,
    required int minutes,
    double? latitude,
    double? longitude,
    double? accuracy,
  }) async {
    final dest = destination.trim();
    final errors = <String, String>{
      if (dest.length < 2) 'destination': 'Nhập nơi bạn đang đi tới.',
      if (dest.length > WalkLimits.maxDestinationLength)
        'destination': 'Nơi đến tối đa ${WalkLimits.maxDestinationLength} ký tự.',
      if (minutes < WalkLimits.minMinutes || minutes > WalkLimits.maxMinutes)
        'minutes': 'Thời gian từ ${WalkLimits.minMinutes} đến ${WalkLimits.maxMinutes} phút.',
      ..._validateCoords(latitude, longitude),
    };
    if (errors.isNotEmpty) throw ApiException.validation(errors);
    if (await _walks.activeFor(user.uid) != null) {
      throw ApiException.conflict('Bạn đang có một lượt "Đi cùng tôi". Kết thúc lượt đó trước.', code: 'walk_active');
    }
    final now = _clock().toUtc();
    final walk = WalkRecord(
      id: _walks.newId(),
      uid: user.uid,
      displayName: user.greetingName,
      phone: user.phone?.local,
      destination: dest,
      startedAt: now,
      dueAt: now.add(Duration(minutes: minutes)),
      status: WalkStatus.active,
      updatedAt: now,
      lastLatitude: latitude,
      lastLongitude: longitude,
      lastAccuracy: accuracy,
      lastLocationAt: latitude == null ? null : now,
    );
    await _walks.save(walk);
    return walk;
  }

  Future<WalkRecord> updateLocation(
    UserRecord user,
    String id, {
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    final errors = _validateCoords(latitude, longitude);
    if (errors.isNotEmpty) throw ApiException.validation(errors);
    await _ownActive(user, id);
    final now = _clock().toUtc();
    return _activeOrEnded(
      id,
      await _walks.updateIfActive(
        id,
        (c) => c.copyWith(
          lastLatitude: latitude,
          lastLongitude: longitude,
          lastAccuracy: accuracy,
          lastLocationAt: now,
          updatedAt: now,
        ),
      ),
    );
  }

  Future<WalkRecord> arrive(UserRecord user, String id) => _finish(user, id, WalkStatus.arrived);

  Future<WalkRecord> cancel(UserRecord user, String id) => _finish(user, id, WalkStatus.cancelled);

  Future<WalkRecord> extend(UserRecord user, String id, int minutes) async {
    if (minutes < WalkLimits.minMinutes || minutes > WalkLimits.maxExtendMinutes) {
      throw ApiException.validation(
        {'minutes': 'Gia hạn từ ${WalkLimits.minMinutes} đến ${WalkLimits.maxExtendMinutes} phút.'},
      );
    }
    await _ownActive(user, id);
    final now = _clock().toUtc();
    final next = await _walks.updateIfActive(id, (c) {
      final base = c.dueAt.isAfter(now) ? c.dueAt : now;
      final due = base.add(Duration(minutes: minutes));
      if (due.difference(c.startedAt) > WalkLimits.maxTotal) {
        throw ApiException.validation({'minutes': 'Một lượt đi tối đa 3 giờ. Hãy kết thúc và bắt đầu lượt mới.'});
      }
      return c.copyWith(dueAt: due, updatedAt: now);
    });
    return _activeOrEnded(id, next);
  }

  /// Người dùng bấm khẩn cấp trong lúc đi: tạo báo cáo khẩn cấp ngay.
  Future<WalkRecord> sos(UserRecord user, String id, {double? latitude, double? longitude, double? accuracy}) async {
    final walk = await _ownActive(user, id);
    final hasFix = latitude != null && longitude != null && _validateCoords(latitude, longitude).isEmpty;
    final raised = await _raise(
      user,
      id,
      WalkStatus.sos,
      'Đi cùng tôi: người dùng bấm KHẨN CẤP trên đường tới ${walk.destination}.',
      latitude: hasFix ? latitude : null,
      longitude: hasFix ? longitude : null,
      accuracy: hasFix ? accuracy : null,
    );
    return _activeOrEnded(id, raised);
  }

  /// Quét các lượt quá giờ. Chạy định kỳ bằng [startOverdueTimer]; trả về số lượt đã báo.
  Future<int> checkOverdue() async {
    if (_checking) return 0;
    _checking = true;
    try {
      final now = _clock().toUtc();
      var raised = 0;
      for (final walk in await _walks.listActive()) {
        if (!walk.isActive || walk.dueAt.isAfter(now)) continue;
        final user = await _users.byId(walk.uid);
        if (user == null || !user.active) {
          await _walks.updateIfActive(walk.id, (c) => c.copyWith(status: WalkStatus.cancelled, endedAt: now, updatedAt: now));
          continue;
        }
        final late = now.difference(walk.dueAt).inMinutes;
        // Một lượt lỗi không được chặn các lượt phía sau; lượt đó được thử lại ở lần quét sau.
        try {
          final done = await _raise(
            user,
            walk.id,
            WalkStatus.overdue,
            'Đi cùng tôi: quá giờ hẹn${late > 0 ? ' $late phút' : ''} mà chưa xác nhận đã tới ${walk.destination}.',
            // Người dùng có thể vừa gia hạn ở máy khác: kiểm tra lại giờ hẹn khi ghi.
            onlyIfDueBefore: now,
          );
          if (done != null) raised++;
        } on Object catch (e) {
          stderr.writeln('[walk] Không báo được lượt ${walk.id}: $e');
        }
      }
      return raised;
    } on Object catch (e) {
      stderr.writeln('[walk] Lỗi quét lượt quá giờ: $e');
      return 0;
    } finally {
      _checking = false;
    }
  }

  void startOverdueTimer({Duration every = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => unawaited(checkOverdue()));
  }

  /// Giành lượt đi (đổi trạng thái nguyên tử) rồi mới tạo báo cáo khẩn cấp, nên dù nhiều
  /// backend cùng quét thì chỉ một báo cáo được tạo. Trả về `null` nếu lượt đã được xử lý.
  Future<WalkRecord?> _raise(
    UserRecord user,
    String id,
    WalkStatus status,
    String note, {
    double? latitude,
    double? longitude,
    double? accuracy,
    DateTime? onlyIfDueBefore,
  }) async {
    final now = _clock().toUtc();
    WalkRecord? before;
    final claimed = await _walks.updateIfActive(id, (c) {
      if (onlyIfDueBefore != null && c.dueAt.isAfter(onlyIfDueBefore)) throw const _NotDue();
      before = c;
      return c.copyWith(
        status: status,
        endedAt: now,
        updatedAt: now,
        lastLatitude: latitude,
        lastLongitude: longitude,
        lastAccuracy: accuracy,
      );
    }).catchError((Object _) => null, test: (e) => e is _NotDue);
    if (claimed == null) return null;

    final ReportRecord report;
    try {
      (report, _) = await _reports.create(
        user,
        ReportDraft(
          type: IncidentType.other,
          severity: Severity.critical,
          description: note,
          occurredAt: now,
          // Không có GPS thì ghi nơi đến làm khu vực để bảo vệ biết hướng tìm.
          building:
              claimed.hasLocation ? null : _clip('Trên đường tới ${claimed.destination}', ReportLimits.maxBuildingLength),
          latitude: claimed.lastLatitude,
          longitude: claimed.lastLongitude,
          accuracyMeters: claimed.lastAccuracy,
          emergency: true,
        ),
      );
    } on Object {
      // Tạo báo cáo thất bại: trả lượt về "đang đi" để lần quét sau (hoặc backend khác) thử lại.
      await _walks.save(before!);
      rethrow;
    }
    final next = claimed.copyWith(reportId: report.id);
    await _walks.save(next);
    if (status == WalkStatus.overdue) {
      unawaited(_notifications.pushTo(
        [user],
        PushMessage(
          title: 'Bạn chưa xác nhận đã tới nơi',
          body: 'Đã báo bảo vệ trực (${report.code}). Nếu bạn an toàn, mở báo cáo để trao đổi với bảo vệ.',
          data: {'type': 'report', 'reportId': report.id},
          urgent: true,
        ),
      ));
    }
    return next;
  }

  Future<WalkRecord> _finish(UserRecord user, String id, WalkStatus status) async {
    await _ownActive(user, id);
    final now = _clock().toUtc();
    return _activeOrEnded(
      id,
      await _walks.updateIfActive(id, (c) => c.copyWith(status: status, endedAt: now, updatedAt: now)),
    );
  }

  /// [next] là `null` khi lượt vừa kết thúc ở nơi khác: báo lỗi kèm trạng thái mới nhất.
  Future<WalkRecord> _activeOrEnded(String id, WalkRecord? next) async {
    if (next != null) return next;
    final latest = await _walks.byId(id);
    throw ApiException.conflict(
      'Lượt đi này đã kết thúc (${latest?.status.label ?? 'không còn'}).',
      code: 'walk_ended',
    );
  }

  Future<WalkRecord> _ownActive(UserRecord user, String id) async {
    final walk = await _walks.byId(id);
    if (walk == null || walk.uid != user.uid) throw ApiException.notFound('Không tìm thấy lượt đi.');
    if (!walk.isActive) {
      throw ApiException.conflict('Lượt đi này đã kết thúc (${walk.status.label}).', code: 'walk_ended');
    }
    return walk;
  }

  static Map<String, String> _validateCoords(double? lat, double? lng) {
    if (lat == null && lng == null) return const {};
    if (lat == null || lng == null || lat.isNaN || lng.isNaN || lat.abs() > 90 || lng.abs() > 180) {
      return {'location': 'Toạ độ GPS không hợp lệ.'};
    }
    return const {};
  }

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);
}

/// Lượt chưa tới giờ hẹn (vừa được gia hạn): huỷ thao tác, không báo quá giờ.
class _NotDue implements Exception {
  const _NotDue();
}

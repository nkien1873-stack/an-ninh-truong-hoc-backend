import 'dart:async';
import 'dart:io';

import 'package:campus_core/campus_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import 'push_service.dart';

/// Kết quả thông báo khi có báo cáo mới, trả về cho app hiển thị ngay.
class ReportCreatedSummary {
  const ReportCreatedSummary({required this.pushDelivered});

  /// Số thiết bị (bảo vệ, quản trị) đã nhận thông báo đẩy.
  final int pushDelivered;

  Map<String, Object?> toJson() => {'pushDelivered': pushDelivered};
}

/// Điều phối thông báo đẩy (FCM) theo sự kiện nghiệp vụ.
///
/// Các phương thức KHÔNG ném lỗi: chúng chạy sau khi dữ liệu đã được lưu, nên lỗi gửi tin
/// không được làm API báo thất bại (người dùng sẽ gửi lại và tạo báo cáo trùng).
class NotificationService {
  NotificationService({
    required PushService push,
    required UserRepository users,
    this.waitLimit = const Duration(seconds: 5),
  })  : _push = push,
        _users = users;

  final PushService _push;
  final UserRepository _users;

  /// Thời gian tối đa API chờ gửi push; quá thì vẫn gửi nốt ở nền.
  final Duration waitLimit;

  Future<ReportCreatedSummary> reportCreated(ReportRecord report, ReporterPrivate reporter) async {
    final staff = await _safe(_users.listStaff, const <UserRecord>[], 'đọc danh sách bảo vệ');
    // Sự cố thường báo quản trị và bảo vệ đang trực; khẩn cấp báo mọi bảo vệ, kể cả đang nghỉ ca.
    final targets = staff.where((u) => u.uid != reporter.uid && (report.emergency || u.onDuty || u.role == UserRole.admin));
    final delivered = await _pushToUsers(
      targets.toList(),
      PushMessage(
        title: report.emergency ? 'KHẨN CẤP: ${report.type.label}' : 'Sự cố mới: ${report.type.label}',
        body: '${report.code}, ${report.locationText}',
        data: {'type': 'report', 'reportId': report.id},
        urgent: true,
      ),
    ).timeout(waitLimit, onTimeout: () => 0);
    return ReportCreatedSummary(pushDelivered: delivered);
  }

  /// Báo trạng thái mới cho người báo.
  Future<void> statusChanged(ReportRecord report, ReporterPrivate reporter, {String? note}) async {
    final reporterUser = await _safe(() => _users.byId(reporter.uid), null, 'đọc hồ sơ người báo');
    await _pushToUsers(
      [?reporterUser],
      PushMessage(
        title: 'Báo cáo ${report.code}: ${report.status.label}',
        body: (note == null || note.isEmpty) ? 'Bấm để xem chi tiết xử lý.' : note,
        data: {'type': 'report', 'reportId': report.id},
      ),
    ).timeout(waitLimit, onTimeout: () => 0);
  }

  /// Người báo huỷ: báo người đang xử lý, hoặc những ai đã nhận cảnh báo lúc tạo nếu chưa ai nhận.
  Future<void> reportCancelled(ReportRecord report, {required String reporterUid}) async {
    final staff = await _safe(_users.listStaff, const <UserRecord>[], 'đọc danh sách bảo vệ');
    final targets = report.assigneeUid != null
        ? staff.where((u) => u.uid == report.assigneeUid)
        : staff.where((u) => report.emergency || u.onDuty || u.role == UserRole.admin);
    await _pushToUsers(
      targets.where((u) => u.uid != reporterUid).toList(),
      PushMessage(
        title: 'Đã huỷ: ${report.code}',
        body: 'Người báo đã huỷ báo cáo ${report.type.label}, ${report.locationText}.',
        data: {'type': 'report', 'reportId': report.id},
      ),
    ).timeout(waitLimit, onTimeout: () => 0);
  }

  Future<void> assigned(ReportRecord report, UserRecord assignee) => _pushToUsers(
    [assignee],
    PushMessage(
      title: 'Bạn được giao xử lý ${report.code}',
      body: '${report.type.label}, ${report.locationText}',
      data: {'type': 'report', 'reportId': report.id},
      urgent: report.severity.rank >= Severity.high.rank,
    ),
  );

  /// Có trao đổi mới: báo cho phía còn lại.
  Future<void> commentAdded(
    ReportRecord report,
    ReporterPrivate reporter, {
    required String authorUid,
    required bool byReporter,
    required String text,
  }) async {
    final List<UserRecord> targets;
    if (byReporter) {
      final staff = await _safe(_users.listStaff, const <UserRecord>[], 'đọc danh sách bảo vệ');
      targets = report.assigneeUid != null
          ? staff.where((u) => u.uid == report.assigneeUid).toList()
          : staff.where((u) => u.onDuty || u.role == UserRole.admin).toList();
    } else {
      targets = [?await _safe(() => _users.byId(reporter.uid), null, 'đọc hồ sơ người báo')];
    }
    await _pushToUsers(
      targets.where((u) => u.uid != authorUid).toList(),
      PushMessage(
        title: 'Trao đổi mới về ${report.code}',
        body: text.length > 120 ? '${text.substring(0, 119)}…' : text,
        data: {'type': 'report', 'reportId': report.id},
      ),
    );
  }

  /// Push tới mọi tài khoản đang hoạt động (cảnh báo toàn trường). Trả về số thiết bị nhận.
  Future<int> pushToAll(PushMessage message) async {
    final users = await _safe(_users.listActive, const <UserRecord>[], 'đọc danh sách tài khoản');
    return _pushToUsers(users, message);
  }

  /// Push tới một số tài khoản cụ thể (ví dụ người đang dùng "Đi cùng tôi").
  Future<int> pushTo(List<UserRecord> users, PushMessage message) => _pushToUsers(users, message);

  static Future<T> _safe<T>(Future<T> Function() run, T fallback, String what) async {
    try {
      return await run();
    } on Object catch (e) {
      stderr.writeln('[notify] Không $what: $e');
      return fallback;
    }
  }

  /// Gửi push và dọn token hết hiệu lực. Trả về số thiết bị nhận thành công.
  Future<int> _pushToUsers(List<UserRecord> users, PushMessage message) async {
    final owner = <String, String>{};
    for (final u in users) {
      for (final t in u.fcmTokens) {
        owner[t] = u.uid;
      }
    }
    if (owner.isEmpty) return 0;
    try {
      final result = await _push.sendToTokens(owner.keys.toList(), message);
      for (final token in result.invalidTokens) {
        final uid = owner[token];
        if (uid != null) await _users.removeFcmToken(uid, token);
      }
      return result.successCount;
    } on Object catch (e) {
      stderr.writeln('[fcm] Lỗi gửi push: $e');
      return 0;
    }
  }
}

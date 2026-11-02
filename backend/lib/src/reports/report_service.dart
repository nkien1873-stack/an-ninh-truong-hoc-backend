import 'package:campus_core/campus_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import '../http/api_exception.dart';
import '../notifications/notification_service.dart';

/// Chi tiết báo cáo trả cho app. [reporter] là `null` khi người xem không được biết người báo.
/// [assignee] là người đang xử lý, để người báo gọi hoặc nhắn sau khi bảo vệ đã nhận.
class ReportDetail {
  const ReportDetail({required this.report, required this.events, this.reporter, this.assignee});

  final ReportRecord report;
  final List<ReportEvent> events;
  final ReporterPrivate? reporter;
  final AssigneeContact? assignee;

  Map<String, Object?> toApiJson() => {
        'report': report.toDetailJson(),
        'events': [
          for (final (i, e) in events.indexed) {'id': '$i', ...e.toApiJson()},
        ],
        'reporter': reporter?.toApiJson(),
        'assignee': assignee?.toApiJson(),
      };
}

/// Nghiệp vụ báo cáo sự cố. Mọi thao tác ghi đều đi qua đây để kiểm tra quyền, kiểm tra dữ
/// liệu và gửi thông báo nhất quán (client chỉ gọi API, không truy cập CSDL).
class ReportService {
  static const listLimit = 300;
  static const sinceLimit = 1000;

  ReportService({
    required ReportRepository reports,
    required UserRepository users,
    required NotificationService notifications,
    Future<void> Function(String uid)? revokeSessions,
    DateTime Function()? clock,
  })  : _reports = reports,
        _users = users,
        _notifications = notifications,
        _revokeSessions = revokeSessions,
        _clock = clock ?? DateTime.now;

  final ReportRepository _reports;
  final UserRepository _users;
  final NotificationService _notifications;

  /// Đăng xuất mọi thiết bị của tài khoản vừa bị tự khoá vì báo sai nhiều lần.
  final Future<void> Function(String uid)? _revokeSessions;
  final DateTime Function() _clock;

  static const fakeNote = 'Báo cáo sai sự thật';

  static const anonymousName = 'Người báo (ẩn danh)';

  Future<(ReportRecord, ReportCreatedSummary)> create(UserRecord actor, ReportDraft draft) async {
    if (!Permissions.canCreateReport(actor.actor)) throw ApiException.forbidden();
    final now = _clock().toUtc();
    final errors = validateReportDraft(draft, now: now);
    if (errors.isNotEmpty) throw ApiException.validation(errors);

    final description = draft.description.trim();
    final report = ReportRecord(
      id: _reports.newId(),
      code: generateReportCode(now: now),
      type: draft.type,
      severity: draft.effectiveSeverity,
      status: ReportStatus.submitted,
      description: description.isEmpty && draft.emergency ? 'Báo cáo khẩn cấp, chưa có mô tả.' : description,
      occurredAt: draft.occurredAt.toUtc(),
      createdAt: now,
      updatedAt: now,
      emergency: draft.emergency,
      anonymous: draft.anonymous,
      building: draft.building,
      floor: draft.floor,
      room: draft.room,
      latitude: draft.latitude,
      longitude: draft.longitude,
      accuracyMeters: draft.accuracyMeters,
      reporterUid: draft.anonymous ? null : actor.uid,
      reporterName: draft.anonymous ? null : (actor.profileComplete ? actor.displayName : null),
      reporterPhone: draft.anonymous ? null : actor.phone?.local,
      reporterMemberType: draft.anonymous ? null : actor.memberType,
      imagePaths: draft.imagePaths,
    );
    final reporter = ReporterPrivate(
      uid: actor.uid,
      email: actor.email,
      phone: actor.phone,
      displayName: actor.displayName,
    );
    await _reports.create(
      report,
      reporter,
      ReportEvent(
        type: ReportEventType.created,
        createdAt: now,
        actorUid: draft.anonymous ? null : actor.uid,
        actorName: draft.anonymous ? anonymousName : _nameOf(actor),
        // Ẩn danh thì không để lộ người báo là bảo vệ hay quản trị.
        actorRole: draft.anonymous ? UserRole.reporter : actor.role,
        toStatus: ReportStatus.submitted,
        note: draft.emergency ? 'Báo cáo khẩn cấp' : null,
      ),
    );
    final summary = await _notifications.reportCreated(report, reporter);
    return (report, summary);
  }

  /// Đổi trạng thái. [fake] chỉ dùng khi từ chối: đánh dấu báo cáo sai sự thật, cộng vào số lần
  /// báo sai của người báo và tự khoá tài khoản khi đủ [FakeReportPolicy.lockThreshold].
  Future<ReportRecord> changeStatus(
    UserRecord actor,
    String reportId, {
    required ReportStatus to,
    String? note,
    bool fake = false,
  }) async {
    if (fake && to != ReportStatus.rejected) {
      throw ApiException.validation({'fake': 'Chỉ đánh dấu báo cáo sai sự thật khi từ chối.'});
    }
    final trimmedNote = note?.trim();
    final now = _clock().toUtc();
    var wasFake = false;
    final (next, reporter) = await _mutate(reportId, (current, _) {
      wasFake = current.fake;
      if (!Permissions.canChangeStatus(actor.actor, assigneeUid: current.assigneeUid)) {
        throw ApiException.forbidden(
          'Báo cáo đang do ${current.assigneeName ?? 'người khác'} xử lý. Liên hệ quản trị nếu cần đổi.',
        );
      }
      final error = ReportStatusMachine.validate(
        from: current.status,
        to: to,
        role: actor.role,
        note: trimmedNote,
      );
      if (error != null) throw ApiException.conflict(error, code: 'invalid_transition');
      final selfAssign = actor.role == UserRole.guard &&
          current.assigneeUid == null &&
          (to == ReportStatus.received || to == ReportStatus.inProgress);
      final next = current.copyWith(
        status: to,
        updatedAt: now,
        assigneeUid: selfAssign ? actor.uid : null,
        assigneeName: selfAssign ? _nameOf(actor) : null,
        // Ghi chú gắn với trạng thái mới; đổi trạng thái không kèm ghi chú thì xoá ghi chú cũ.
        lastNote: (trimmedNote?.isNotEmpty ?? false) ? trimmedNote : null,
        clearLastNote: !(trimmedNote?.isNotEmpty ?? false),
        closedAt: to.isClosed ? now : null,
        clearClosedAt: !to.isClosed,
        // Mở lại báo cáo thì bỏ dấu báo sai (quản trị xác nhận đã đánh dấu nhầm).
        fake: fake,
      );
      final noteText = (trimmedNote?.isNotEmpty ?? false) ? trimmedNote : null;
      return (
        next,
        ReportEvent(
          type: ReportEventType.status,
          createdAt: now,
          actorUid: actor.uid,
          actorName: _nameOf(actor),
          actorRole: actor.role,
          fromStatus: current.status,
          toStatus: to,
          note: fake ? '$fakeNote${noteText == null ? '' : ': $noteText'}' : noteText,
        ),
      );
    });
    await _notifications.statusChanged(next, reporter, note: fake ? '$fakeNote. $trimmedNote' : trimmedNote);
    if (fake != wasFake) await _countFake(reporter.uid, fake ? 1 : -1);
    return next;
  }

  /// Cộng/trừ số lần báo sai. Người báo (không phải bảo vệ/quản trị) đủ ngưỡng thì bị khoá.
  Future<void> _countFake(String uid, int delta) async {
    final user = await _users.addFakeReports(uid, delta);
    if (user == null || delta < 0) return;
    if (user.active && user.role == UserRole.reporter && user.fakeReports >= FakeReportPolicy.lockThreshold) {
      await _users.update(uid, active: false);
      await _revokeSessions?.call(uid);
    }
  }

  /// Người báo tự huỷ báo cáo của mình khi bảo vệ chưa bắt đầu xử lý. Báo cáo vẫn được lưu với
  /// trạng thái "Đã huỷ" để tra cứu.
  Future<ReportRecord> cancel(UserRecord actor, String reportId, {String? reason}) async {
    final trimmed = reason?.trim() ?? '';
    if (trimmed.length > ReportStatusMachine.maxCancelReasonLength) {
      throw ApiException.validation({'reason': 'Lý do tối đa ${ReportStatusMachine.maxCancelReasonLength} ký tự.'});
    }
    final now = _clock().toUtc();
    final (next, _) = await _mutate(reportId, (current, reporter) {
      if (reporter.uid != actor.uid) throw ApiException.forbidden('Chỉ người gửi được huỷ báo cáo này.');
      if (!ReportStatusMachine.canCancel(current.status)) {
        throw ApiException.conflict(
          current.status.isClosed
              ? 'Báo cáo đã đóng (${current.status.label}).'
              : 'Bảo vệ đang xử lý, không thể huỷ. Hãy nhắn bảo vệ nếu sự cố đã ổn.',
          code: 'cannot_cancel',
        );
      }
      return (
        current.copyWith(
          status: ReportStatus.cancelled,
          updatedAt: now,
          lastNote: trimmed.isEmpty ? null : trimmed,
          clearLastNote: trimmed.isEmpty,
          closedAt: now,
        ),
        ReportEvent(
          type: ReportEventType.status,
          createdAt: now,
          actorUid: current.anonymous ? null : actor.uid,
          actorName: current.anonymous ? anonymousName : _nameOf(actor),
          actorRole: UserRole.reporter,
          fromStatus: current.status,
          toStatus: ReportStatus.cancelled,
          note: trimmed.isEmpty ? 'Người báo đã huỷ' : 'Người báo đã huỷ: $trimmed',
        ),
      );
    });
    await _notifications.reportCancelled(next, reporterUid: actor.uid);
    return next;
  }

  /// Phân công. Nếu báo cáo còn "Đã gửi" thì chuyển sang "Đã tiếp nhận" và báo người báo.
  Future<ReportRecord> assign(UserRecord actor, String reportId, String targetUid) async {
    final target = await _users.byId(targetUid);
    if (target == null || !target.active || !target.role.isStaff) {
      throw ApiException.badRequest('Chỉ giao được cho bảo vệ hoặc quản trị đang hoạt động.');
    }
    final now = _clock().toUtc();
    var statusChanged = false;
    final (next, reporter) = await _mutate(reportId, (current, _) {
      if (!Permissions.canAssign(actor.actor, targetUid: targetUid, currentAssigneeUid: current.assigneeUid)) {
        throw ApiException.forbidden('Bạn chỉ tự nhận được báo cáo chưa có người xử lý.');
      }
      if (current.status.isClosed) {
        throw ApiException.conflict('Báo cáo đã đóng, không thể phân công.', code: 'report_closed');
      }
      if (current.assigneeUid == targetUid) {
        throw ApiException.conflict('Báo cáo đã được giao cho người này.', code: 'already_assigned');
      }
      statusChanged = current.status == ReportStatus.submitted;
      final newStatus = statusChanged ? ReportStatus.received : current.status;
      return (
        current.copyWith(
          status: newStatus,
          updatedAt: now,
          assigneeUid: target.uid,
          assigneeName: _nameOf(target),
        ),
        ReportEvent(
          type: ReportEventType.assigned,
          createdAt: now,
          actorUid: actor.uid,
          actorName: _nameOf(actor),
          actorRole: actor.role,
          fromStatus: statusChanged ? current.status : null,
          toStatus: statusChanged ? newStatus : null,
          note: actor.uid == target.uid ? '${_nameOf(target)} nhận xử lý' : 'Giao cho ${_nameOf(target)}',
        ),
      );
    });
    await _notifications.assigned(next, target);
    if (statusChanged) await _notifications.statusChanged(next, reporter);
    return next;
  }

  /// Chi tiết một báo cáo cho [actor]. Người báo thật chỉ có với quản trị và chính người báo.
  Future<ReportDetail> detail(UserRecord actor, String reportId) async {
    final report = await _reports.byId(reportId);
    final reporter = await _reports.reporterOf(reportId);
    if (report == null || reporter == null) throw ApiException.notFound('Không tìm thấy báo cáo.');
    final isOwner = reporter.uid == actor.uid;
    if (!Permissions.canViewReport(actor.actor, isOwner: isOwner)) throw ApiException.forbidden();
    final assigneeUid = report.assigneeUid;
    final assignee = assigneeUid == null ? null : await _users.byId(assigneeUid);
    return ReportDetail(
      report: report,
      events: await _reports.eventsOf(reportId),
      reporter: (isOwner || actor.role == UserRole.admin) ? reporter : null,
      assignee: assignee == null
          ? null
          : AssigneeContact(uid: assignee.uid, displayName: _nameOf(assignee), phone: assignee.phone),
    );
  }

  /// Danh sách báo cáo. `mine` cho mọi người; `open`, `assigned`, `since` chỉ cho bảo vệ và quản trị.
  Future<List<ReportRecord>> list(UserRecord actor, {required String scope, DateTime? from}) {
    if (scope == 'mine') return _reports.listByReporter(actor.uid, limit: listLimit);
    if (!Permissions.canViewAllReports(actor.actor)) throw ApiException.forbidden();
    return switch (scope) {
      'open' => _reports.listOpen(limit: listLimit),
      'assigned' => _reports.listAssignedTo(actor.uid, limit: listLimit),
      'since' when from != null => _reports.listSince(from, limit: sinceLimit),
      _ => throw ApiException.validation({'scope': 'Danh sách báo cáo không hợp lệ.'}),
    };
  }

  Future<void> comment(UserRecord actor, String reportId, String text) async {
    final report = await _reports.byId(reportId);
    final reporter = await _reports.reporterOf(reportId);
    if (report == null || reporter == null) throw ApiException.notFound('Không tìm thấy báo cáo.');
    final isOwner = reporter.uid == actor.uid;
    if (!Permissions.canComment(actor.actor, isOwner: isOwner)) throw ApiException.forbidden();
    // Như gọi xe: người báo nhắn được khi đã có bảo vệ nhận báo cáo.
    if (isOwner && !actor.role.isStaff && report.status.isOpen && report.assigneeUid == null) {
      throw ApiException.conflict(
        'Chờ bảo vệ nhận báo cáo rồi mới nhắn được. Nếu khẩn cấp, hãy gọi trực an ninh.',
        code: 'not_assigned',
      );
    }
    final error = validateComment(text);
    if (error != null) throw ApiException.validation({'text': error});
    final hidden = isOwner && report.anonymous;
    final trimmed = text.trim();
    await _reports.addEvent(
      reportId,
      ReportEvent(
        type: ReportEventType.comment,
        createdAt: _clock().toUtc(),
        actorUid: hidden ? null : actor.uid,
        actorName: hidden ? anonymousName : _nameOf(actor),
        actorRole: isOwner ? UserRole.reporter : actor.role,
        note: trimmed,
      ),
    );
    await _notifications.commentAdded(
      report,
      reporter,
      authorUid: actor.uid,
      byReporter: isOwner && !actor.role.isStaff,
      text: trimmed,
    );
  }

  Future<(ReportRecord, ReporterPrivate)> _mutate(
    String id,
    (ReportRecord, ReportEvent?) Function(ReportRecord, ReporterPrivate) apply,
  ) async {
    try {
      return await _reports.mutate(id, apply);
    } on StateError catch (e) {
      if (e.message == 'report_not_found') throw ApiException.notFound('Không tìm thấy báo cáo.');
      throw ApiException.conflict('Báo cáo đang được cập nhật. Hãy thử lại.', code: 'write_conflict');
    }
  }

  static String _nameOf(UserRecord u) =>
      u.profileComplete ? u.displayName : '${u.role.label} ${u.email.masked}';
}

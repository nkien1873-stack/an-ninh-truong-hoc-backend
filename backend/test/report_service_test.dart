import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

class _FlakyUsers extends MemoryUserRepository {
  @override
  Future<List<UserRecord>> listStaff() => throw StateError('CSDL không truy cập được');
}

class _ConflictReports extends MemoryReportRepository {
  @override
  Future<(ReportRecord, ReporterPrivate)> mutate(
    String id,
    (ReportRecord, ReportEvent?) Function(ReportRecord current, ReporterPrivate reporter) apply,
  ) =>
      throw StateError('report_write_conflict');
}

void main() {
  late TestClock clock;
  late MemoryUserRepository users;
  late MemoryReportRepository reports;
  late RecordingPushService push;
  late ReportService service;
  late UserRecord student, guardOnDuty, guardOff, admin;

  setUp(() {
    clock = TestClock(DateTime.utc(2026, 10, 19, 7));
    users = MemoryUserRepository();
    reports = MemoryReportRepository();
    push = RecordingPushService();
    student = users.seed(phone: '0912345678', name: 'Trần Minh Khoa', tokens: ['tok-student']);
    guardOnDuty = users.seed(phone: '0987654321', name: 'Lê Văn Hùng', role: UserRole.guard, onDuty: true, tokens: ['tok-g1']);
    guardOff = users.seed(phone: '0977111222', name: 'Phạm Quốc Bảo', role: UserRole.guard, tokens: ['tok-g2']);
    admin = users.seed(phone: '0901234567', name: 'Đỗ Thu Hà', role: UserRole.admin, tokens: ['tok-admin']);
    service = ReportService(
      reports: reports,
      users: users,
      clock: clock.call,
      notifications: NotificationService(push: push, users: users),
    );
  });

  ReportDraft draft({bool anonymous = false, bool emergency = false}) => ReportDraft(
        type: IncidentType.theft,
        severity: Severity.high,
        description: emergency ? '' : 'Mất xe đạp ở bãi xe B, khoá bị cắt',
        occurredAt: clock.now.subtract(const Duration(minutes: 20)),
        building: 'Bãi xe',
        latitude: emergency ? 21.0285 : null,
        longitude: emergency ? 105.8542 : null,
        anonymous: anonymous,
        emergency: emergency,
      );

  test('tạo báo cáo: lưu trạng thái Đã gửi, có mã sự cố, chỉ báo bảo vệ đang trực và quản trị', () async {
    final (report, summary) = await service.create(student, draft());
    expect(report.status, ReportStatus.submitted);
    expect(reportCodePattern.hasMatch(report.code), isTrue);

    final (tokens, message) = push.sent.single;
    expect(tokens.toSet(), {'tok-g1', 'tok-admin'}, reason: 'bảo vệ nghỉ ca không bị làm phiền');
    expect(message.urgent, isTrue);
    expect(message.data['reportId'], report.id);
    expect(summary.pushDelivered, 2);
  });

  test('sự cố khẩn cấp báo mọi bảo vệ, kể cả đang nghỉ ca', () async {
    await service.create(student, draft(emergency: true));
    final (tokens, message) = push.sent.single;
    expect(tokens.toSet(), {'tok-g1', 'tok-g2', 'tok-admin'});
    expect(message.title, startsWith('KHẨN CẤP'));
  });

  test('báo cáo ẩn danh: không lưu tên/số người báo trong tài liệu bảo vệ đọc được', () async {
    final (report, _) = await service.create(student, draft(anonymous: true));
    expect(report.reporterUid, isNull);
    expect(report.reporterName, isNull);
    expect(report.reporterPhone, isNull);
    expect(reports.events[report.id]!.single.actorName, 'Người báo (ẩn danh)');
    expect(reports.events[report.id]!.single.actorUid, isNull);
    // Người báo vẫn theo dõi được báo cáo của mình.
    expect(reports.privates[report.id]!.phone, student.phone);
    expect(reports.userIndex[student.uid], contains(report.id));
  });

  test('người dùng chưa có số điện thoại vẫn gửi và nhận thông báo bình thường', () async {
    final noPhone = users.seed(email: 'khong.so@gmail.com', name: 'Vũ An', tokens: ['tok-np']);
    final (report, summary) = await service.create(noPhone, draft());
    expect(report.reporterPhone, isNull);
    expect(reports.privates[report.id]!.email!.value, 'khong.so@gmail.com');
    expect(summary.pushDelivered, 2);

    push.sent.clear();
    await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received);
    expect(push.sent.single.$1, ['tok-np']);
  });

  test('báo cáo khẩn cấp: mức Khẩn cấp, chấp nhận không mô tả nếu có GPS', () async {
    final (report, _) = await service.create(student, draft(emergency: true));
    expect(report.severity, Severity.critical);
    expect(report.emergency, isTrue);
    expect(report.description, isNotEmpty);
  });

  test('dữ liệu sai: trả lỗi 422 theo từng trường', () async {
    final bad = ReportDraft(
      type: IncidentType.fight,
      severity: Severity.low,
      description: 'ngắn',
      occurredAt: clock.now,
    );
    await expectLater(
      service.create(student, bad),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'status', 422)
          .having((e) => (e.details!['fields'] as Map).keys, 'fields', containsAll(['description', 'building']))),
    );
  });

  test('bảo vệ tiếp nhận: tự nhận việc, người báo nhận thông báo cập nhật trạng thái', () async {
    final (report, _) = await service.create(student, draft());
    push.sent.clear();
    final updated = await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received);
    expect(updated.status, ReportStatus.received);
    expect(updated.assigneeUid, guardOnDuty.uid);
    final (tokens, message) = push.sent.single;
    expect(tokens, ['tok-student']);
    expect(message.title, contains('Đã tiếp nhận'));
    final event = reports.events[report.id]!.last;
    expect(event.fromStatus, ReportStatus.submitted);
    expect(event.toStatus, ReportStatus.received);
  });

  test('người báo không đổi được trạng thái; bảo vệ khác không giành việc', () async {
    final (report, _) = await service.create(student, draft());
    await expectLater(
      service.changeStatus(student, report.id, to: ReportStatus.received),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.inProgress);
    await expectLater(
      service.changeStatus(guardOff, report.id, to: ReportStatus.resolved),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('Lê Văn Hùng'))),
    );
    // Quản trị vẫn đóng được.
    final closed = await service.changeStatus(admin, report.id, to: ReportStatus.resolved, note: 'Đã tìm thấy xe');
    expect(closed.closedAt, clock.now);
    expect(closed.lastNote, 'Đã tìm thấy xe');
  });

  test('từ chối bắt buộc lý do; chuyển sai luồng bị chặn', () async {
    final (report, _) = await service.create(student, draft());
    await expectLater(
      service.changeStatus(guardOnDuty, report.id, to: ReportStatus.rejected),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_transition')),
    );
    await expectLater(
      service.changeStatus(guardOnDuty, report.id, to: ReportStatus.resolved),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('quản trị phân công: báo cáo chuyển Đã tiếp nhận, bảo vệ được giao nhận push', () async {
    final (report, _) = await service.create(student, draft());
    push.sent.clear();
    final assigned = await service.assign(admin, report.id, guardOff.uid);
    expect(assigned.assigneeUid, guardOff.uid);
    expect(assigned.status, ReportStatus.received);
    expect(push.sent.any((p) => p.$1.contains('tok-g2')), isTrue);
    expect(push.sent.any((p) => p.$1.contains('tok-student')), isTrue, reason: 'người báo biết đã được tiếp nhận');
  });

  test('bảo vệ không giao việc cho người khác; không giao cho người báo', () async {
    final (report, _) = await service.create(student, draft());
    await expectLater(service.assign(guardOnDuty, report.id, guardOff.uid), throwsA(isA<ApiException>()));
    await expectLater(service.assign(admin, report.id, student.uid), throwsA(isA<ApiException>()));
  });

  test('trao đổi: người báo ẩn danh vẫn ẩn tên; người khác không bình luận được', () async {
    final (report, _) = await service.create(student, draft(anonymous: true));
    await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received);
    await service.comment(student, report.id, 'Xe màu xanh, biển 29B1-123.45');
    final event = reports.events[report.id]!.last;
    expect(event.type, ReportEventType.comment);
    expect(event.actorName, 'Người báo (ẩn danh)');
    expect(event.actorUid, isNull);

    final stranger = users.seed(phone: '0966000111', name: 'Hoàng Gia Linh');
    await expectLater(service.comment(stranger, report.id, 'xin chào'), throwsA(isA<ApiException>()));
  });

  test('token push hết hiệu lực được dọn khỏi hồ sơ', () async {
    push.invalid.add('tok-g1');
    await service.create(student, draft());
    expect(users.byUid[guardOnDuty.uid]!.fcmTokens, isEmpty);
  });

  test('đọc danh sách bảo vệ lỗi: báo cáo vẫn tạo thành công', () async {
    final flaky = _FlakyUsers();
    final reporterUser = flaky.seed(phone: '0912345678', name: 'Trần Minh Khoa');
    final svc = ReportService(
      reports: reports,
      users: flaky,
      clock: clock.call,
      notifications: NotificationService(push: push, users: flaky),
    );
    final (report, summary) = await svc.create(reporterUser, draft());
    expect(reports.reports[report.id], isNotNull);
    expect(summary.pushDelivered, 0);
  });

  test('bảo vệ gửi ẩn danh: lịch sử không lộ vai trò bảo vệ', () async {
    final (report, _) = await service.create(guardOff, draft(anonymous: true));
    final created = reports.events[report.id]!.single;
    expect(created.actorRole, UserRole.reporter);
    expect(created.actorUid, isNull);
  });

  test('người báo chỉ nhắn được khi đã có bảo vệ nhận; tin nhắn tới đúng bảo vệ đó', () async {
    final (report, _) = await service.create(student, draft());
    await expectLater(
      service.comment(student, report.id, 'Xe màu xanh'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_assigned')),
    );
    // Bảo vệ vẫn hỏi thêm được trước khi nhận.
    await service.comment(guardOff, report.id, 'Bạn đang ở đâu?');

    await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received);
    push.sent.clear();
    await service.comment(student, report.id, 'Xe màu xanh');
    expect(push.sent.single.$1, ['tok-g1']);
  });

  test('chi tiết có người đang xử lý kèm số điện thoại để người báo gọi', () async {
    final (report, _) = await service.create(student, draft());
    expect((await service.detail(student, report.id)).toApiJson()['assignee'], isNull);
    await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received);
    final assignee = (await service.detail(student, report.id)).toApiJson()['assignee']! as Map;
    expect(assignee['displayName'], 'Lê Văn Hùng');
    expect(assignee['phoneLocal'], '0987654321');
  });

  group('người báo huỷ', () {
    test('huỷ khi chưa xử lý: lưu trạng thái Đã huỷ, giữ mã, báo bảo vệ đang trực và quản trị', () async {
      final (report, _) = await service.create(student, draft());
      push.sent.clear();
      final cancelled = await service.cancel(student, report.id, reason: 'Đã tìm thấy xe');
      expect(cancelled.status, ReportStatus.cancelled);
      expect(cancelled.code, report.code);
      expect(cancelled.closedAt, isNotNull);
      expect(reports.reports[report.id]!.status, ReportStatus.cancelled);
      expect(reports.events[report.id]!.last.note, 'Người báo đã huỷ: Đã tìm thấy xe');
      expect(push.sent.single.$1.toSet(), {'tok-g1', 'tok-admin'});
      expect(await reports.listOpen(limit: 10), isEmpty);
    });

    test('đã có bảo vệ nhận: chỉ báo bảo vệ đó; ẩn danh vẫn ẩn tên trong lịch sử', () async {
      final (report, _) = await service.create(student, draft(anonymous: true));
      await service.changeStatus(guardOff, report.id, to: ReportStatus.received);
      push.sent.clear();
      await service.cancel(student, report.id);
      expect(push.sent.single.$1, ['tok-g2']);
      expect(reports.events[report.id]!.last.actorName, 'Người báo (ẩn danh)');
      expect(reports.events[report.id]!.last.actorUid, isNull);
    });

    test('bảo vệ đang xử lý, báo cáo đã đóng, hoặc người khác: không huỷ được', () async {
      final (report, _) = await service.create(student, draft());
      await expectLater(service.cancel(guardOnDuty, report.id), throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)));
      await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.inProgress);
      await expectLater(
        service.cancel(student, report.id),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'cannot_cancel')),
      );
      await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.resolved);
      await expectLater(service.cancel(student, report.id), throwsA(isA<ApiException>()));
    });

    test('báo cáo đã huỷ không đổi trạng thái được nữa, kể cả quản trị', () async {
      final (report, _) = await service.create(student, draft());
      await service.cancel(student, report.id);
      await expectLater(
        service.changeStatus(admin, report.id, to: ReportStatus.received),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'invalid_transition')),
      );
    });
  });

  group('báo cáo sai sự thật', () {
    Future<void> rejectFake(UserRecord reporter, {bool anonymous = false}) async {
      final (report, _) = await service.create(reporter, draft(anonymous: anonymous));
      await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.rejected, note: 'Kiểm tra không có gì', fake: true);
    }

    test('đánh dấu khi từ chối: lưu dấu, ghi lịch sử, cộng số lần báo sai', () async {
      final (report, _) = await service.create(student, draft());
      final next = await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.rejected, note: 'Không có xe nào mất', fake: true);
      expect(next.fake, isTrue);
      expect(reports.events[report.id]!.last.note, 'Báo cáo sai sự thật: Không có xe nào mất');
      expect(users.byUid[student.uid]!.fakeReports, 1);
      expect(users.byUid[student.uid]!.active, isTrue);
    });

    test('chỉ đánh dấu được khi từ chối', () async {
      final (report, _) = await service.create(student, draft());
      await expectLater(
        service.changeStatus(guardOnDuty, report.id, to: ReportStatus.received, fake: true),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 422)),
      );
    });

    test('đủ 3 lần (kể cả báo ẩn danh) thì tự khoá tài khoản và đăng xuất mọi máy', () async {
      final revoked = <String>[];
      service = ReportService(
        reports: reports,
        users: users,
        clock: clock.call,
        notifications: NotificationService(push: push, users: users),
        revokeSessions: (uid) async => revoked.add(uid),
      );
      await rejectFake(student);
      await rejectFake(student, anonymous: true);
      expect(users.byUid[student.uid]!.active, isTrue);
      await rejectFake(student);
      expect(users.byUid[student.uid]!.fakeReports, 3);
      expect(users.byUid[student.uid]!.active, isFalse);
      expect(revoked, [student.uid]);
    });

    test('quản trị mở lại báo cáo bị đánh dấu nhầm thì trừ lại số lần', () async {
      final (report, _) = await service.create(student, draft());
      await service.changeStatus(guardOnDuty, report.id, to: ReportStatus.rejected, note: 'Kiểm tra không có gì', fake: true);
      final reopened = await service.changeStatus(admin, report.id, to: ReportStatus.received);
      expect(reopened.fake, isFalse);
      expect(users.byUid[student.uid]!.fakeReports, 0);
    });

    test('bảo vệ hoặc quản trị gửi báo cáo bị đánh dấu sai: đếm nhưng không tự khoá', () async {
      for (var i = 0; i < 3; i++) {
        await rejectFake(guardOff);
      }
      expect(users.byUid[guardOff.uid]!.fakeReports, 3);
      expect(users.byUid[guardOff.uid]!.active, isTrue);
    });
  });

  test('ghi xung đột quá nhiều lần báo 409, không báo "không tìm thấy"', () async {
    final svc = ReportService(
      reports: _ConflictReports(),
      users: users,
      clock: clock.call,
      notifications: NotificationService(push: push, users: users),
    );
    await expectLater(
      svc.changeStatus(admin, 'r1', to: ReportStatus.received),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 409)),
    );
  });

  test('xem chi tiết: người lạ bị chặn; bảo vệ không thấy người báo; quản trị và chính chủ thấy', () async {
    final (report, _) = await service.create(student, draft(anonymous: true));
    final stranger = users.seed(phone: '0966000222', name: 'Người lạ');

    await expectLater(
      service.detail(stranger, report.id),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    final forGuard = (await service.detail(guardOnDuty, report.id)).toApiJson();
    expect(forGuard['reporter'], isNull);
    expect((forGuard['report']! as Map)['reporterUid'], isNull);
    expect((await service.detail(admin, report.id)).reporter?.uid, student.uid);
    final own = (await service.detail(student, report.id)).toApiJson();
    expect((own['reporter']! as Map)['uid'], student.uid);
    expect(own['events'], hasLength(1));
  });

  test('danh sách: người báo chỉ xem báo cáo của mình, kể cả ẩn danh', () async {
    final (mine, _) = await service.create(student, draft(anonymous: true));
    await service.create(guardOff, draft());
    expect((await service.list(student, scope: 'mine')).map((r) => r.id), [mine.id]);
    for (final scope in ['open', 'assigned', 'since']) {
      await expectLater(
        () => service.list(student, scope: scope, from: clock.now),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
      );
    }
    expect(await service.list(admin, scope: 'open'), hasLength(2));
    await expectLater(() => service.list(admin, scope: 'la'), throwsA(isA<ApiException>()));
  });

  test('đổi trạng thái không kèm ghi chú thì xoá ghi chú cũ', () async {
    final (report, _) = await service.create(student, draft());
    await service.changeStatus(admin, report.id, to: ReportStatus.rejected, note: 'Báo cáo trùng lặp');
    expect(reports.reports[report.id]!.lastNote, 'Báo cáo trùng lặp');
    await service.changeStatus(admin, report.id, to: ReportStatus.received);
    expect(reports.reports[report.id]!.lastNote, isNull);
  });
}

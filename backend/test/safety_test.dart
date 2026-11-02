import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

class _MemoryBroadcasts implements BroadcastRepository {
  final items = <String, BroadcastRecord>{};
  var _seq = 0;

  @override
  String newId() => 'b${++_seq}';

  @override
  Future<void> create(BroadcastRecord record) async => items[record.id] = record;

  @override
  Future<BroadcastRecord?> byId(String id) async => items[id];

  @override
  Future<List<BroadcastRecord>> recent({required int limit}) async => items.values.take(limit).toList();

  @override
  Future<void> end(String id, DateTime at) async {
    final b = items[id]!;
    items[id] = BroadcastRecord(
      id: b.id,
      title: b.title,
      body: b.body,
      level: b.level,
      createdAt: b.createdAt,
      expiresAt: b.expiresAt,
      createdByUid: b.createdByUid,
      createdByName: b.createdByName,
      active: false,
      endedAt: at,
    );
  }
}

class _MemoryWalks implements WalkRepository {
  final items = <String, WalkRecord>{};
  var _seq = 0;

  @override
  String newId() => 'w${++_seq}';

  @override
  Future<WalkRecord?> byId(String id) async => items[id];

  @override
  Future<WalkRecord?> activeFor(String uid) async =>
      items.values.where((w) => w.uid == uid && w.isActive).firstOrNull;

  @override
  Future<List<WalkRecord>> listActive() async => items.values.where((w) => w.isActive).toList();

  @override
  Future<void> save(WalkRecord walk) async => items[walk.id] = walk;

  @override
  Future<WalkRecord?> updateIfActive(String id, WalkRecord Function(WalkRecord current) update) async {
    final current = items[id];
    if (current == null || !current.isActive) return null;
    return items[id] = update(current);
  }
}

void main() {
  late TestClock clock;
  late MemoryUserRepository users;
  late MemoryReportRepository reports;
  late RecordingPushService push;
  late NotificationService notifications;
  late UserRecord student, guard, admin;

  setUp(() {
    clock = TestClock(DateTime.utc(2026, 10, 25, 13));
    users = MemoryUserRepository();
    reports = MemoryReportRepository();
    push = RecordingPushService();
    notifications = NotificationService(push: push, users: users);
    student = users.seed(email: 'khoa@gmail.com', name: 'Trần Minh Khoa', tokens: ['tok-s']);
    guard = users.seed(name: 'Lê Văn Hùng', role: UserRole.guard, onDuty: true, tokens: ['tok-g']);
    admin = users.seed(name: 'Đỗ Thu Hà', role: UserRole.admin, tokens: ['tok-a']);
    users.seed(name: 'Đã khoá', active: false, tokens: ['tok-locked']);
  });

  TypeMatcher<ApiException> apiError(String code) => isA<ApiException>().having((e) => e.code, 'code', code);

  group('Cảnh báo toàn trường', () {
    late _MemoryBroadcasts store;
    late BroadcastService service;

    setUp(() {
      store = _MemoryBroadcasts();
      service = BroadcastService(broadcasts: store, notifications: notifications, clock: clock.call);
    });

    test('lưu cảnh báo và push tới mọi tài khoản đang hoạt động', () async {
      final (record, delivered) = await service.send(
        admin,
        title: 'Cháy ở toà B',
        body: 'Tránh khu vực toà B, di chuyển ra sân trường.',
        level: BroadcastLevel.danger,
        hours: 2,
      );
      expect(store.items[record.id]!.active, isTrue);
      expect(record.expiresAt, clock.now.add(const Duration(hours: 2)));
      expect(delivered, 3);
      final (tokens, message) = push.sent.single;
      expect(tokens.toSet(), {'tok-s', 'tok-g', 'tok-a'});
      expect(message.urgent, isTrue);
      expect(message.title, 'Nguy hiểm: Cháy ở toà B');
      expect(message.data['type'], 'broadcast');
    });

    test('chỉ quản trị gửi được; kiểm tra độ dài và thời gian', () async {
      await expectLater(
        service.send(guard, title: 'abc', body: 'abc', level: BroadcastLevel.info),
        throwsA(apiError('forbidden')),
      );
      await expectLater(
        service.send(admin, title: 'a', body: 'Nội dung', level: BroadcastLevel.info, hours: 100),
        throwsA(isA<ApiException>().having((e) => e.details?['fields'], 'fields', allOf(contains('title'), contains('hours')))),
      );
    });

    test('gỡ cảnh báo trước hạn', () async {
      final (record, _) = await service.send(admin, title: 'Mưa bão', body: 'Nghỉ học chiều nay.', level: BroadcastLevel.warning);
      await service.end(admin, record.id);
      expect(store.items[record.id]!.active, isFalse);
      await expectLater(service.end(admin, 'khong-co'), throwsA(apiError('not_found')));
    });
  });

  group('Đi cùng tôi', () {
    late _MemoryWalks store;
    late WalkService service;

    setUp(() {
      store = _MemoryWalks();
      service = WalkService(
        walks: store,
        users: users,
        reports: ReportService(reports: reports, users: users, notifications: notifications, clock: clock.call),
        notifications: notifications,
        clock: clock.call,
      );
    });

    test('bắt đầu, cập nhật vị trí, tới nơi: không tạo báo cáo', () async {
      final walk = await service.start(student, destination: 'Ký túc xá khu B', minutes: 15);
      expect(walk.dueAt, clock.now.add(const Duration(minutes: 15)));
      await service.updateLocation(student, walk.id, latitude: 10.76, longitude: 106.68, accuracy: 8);
      expect(store.items[walk.id]!.lastLatitude, 10.76);
      final done = await service.arrive(student, walk.id);
      expect(done.status, WalkStatus.arrived);
      clock.advance(const Duration(hours: 1));
      expect(await service.checkOverdue(), 0);
      expect(reports.reports, isEmpty);
    });

    test('mỗi người chỉ một lượt; người khác không sửa được lượt của mình', () async {
      final walk = await service.start(student, destination: 'Cổng sau', minutes: 10);
      await expectLater(service.start(student, destination: 'Thư viện', minutes: 10), throwsA(apiError('walk_active')));
      await expectLater(service.arrive(guard, walk.id), throwsA(apiError('not_found')));
    });

    test('quá giờ: tạo báo cáo khẩn cấp kèm vị trí cuối, báo bảo vệ, push cho người đi', () async {
      final walk = await service.start(student, destination: 'Bãi xe B', minutes: 10, latitude: 10.7, longitude: 106.6);
      clock.advance(const Duration(minutes: 9));
      expect(await service.checkOverdue(), 0);
      clock.advance(const Duration(minutes: 3));
      expect(await service.checkOverdue(), 1);

      final ended = store.items[walk.id]!;
      expect(ended.status, WalkStatus.overdue);
      final report = reports.reports[ended.reportId]!;
      expect(report.emergency, isTrue);
      expect(report.severity, Severity.critical);
      expect(report.latitude, 10.7);
      expect(report.description, contains('Bãi xe B'));
      expect(push.sent.any((p) => p.$1.contains('tok-g')), isTrue, reason: 'bảo vệ nhận cảnh báo sự cố');
      expect(push.sent.any((p) => p.$1.contains('tok-s') && p.$2.title.contains('chưa xác nhận')), isTrue);
      expect(await service.checkOverdue(), 0, reason: 'không báo lặp');
    });

    test('quá giờ khi không có GPS: ghi nơi đến làm khu vực', () async {
      final walk = await service.start(student, destination: 'Nhà xe', minutes: 5);
      clock.advance(const Duration(minutes: 6));
      await service.checkOverdue();
      final report = reports.reports[store.items[walk.id]!.reportId]!;
      expect(report.building, 'Trên đường tới Nhà xe');
    });

    test('gia hạn đẩy giờ hẹn; tối đa 3 giờ một lượt', () async {
      final walk = await service.start(student, destination: 'Thư viện', minutes: 120);
      final extended = await service.extend(student, walk.id, 30);
      expect(extended.dueAt, walk.dueAt.add(const Duration(minutes: 30)));
      await service.extend(student, walk.id, 30);
      await expectLater(service.extend(student, walk.id, 5), throwsA(apiError('validation_failed')));
    });

    test('bấm khẩn cấp: tạo báo cáo ngay, kết thúc lượt', () async {
      final walk = await service.start(student, destination: 'Sân bóng', minutes: 20);
      final sos = await service.sos(student, walk.id, latitude: 10.8, longitude: 106.7);
      expect(sos.status, WalkStatus.sos);
      expect(reports.reports[sos.reportId]!.latitude, 10.8);
      await expectLater(service.cancel(student, walk.id), throwsA(apiError('walk_ended')));
    });

    group('nhiều backend dùng chung CSDL', () {
      // Mỗi laptop chạy một backend riêng nhưng cùng database: dùng chung kho lượt đi và báo cáo.
      WalkService backend() => WalkService(
            walks: store,
            users: users,
            reports: ReportService(reports: reports, users: users, notifications: notifications, clock: clock.call),
            notifications: notifications,
            clock: clock.call,
          );

      test('3 backend quét cùng lúc: chỉ tạo 1 báo cáo quá giờ', () async {
        final walk = await service.start(student, destination: 'Bãi xe B', minutes: 10, latitude: 10.7, longitude: 106.6);
        clock.advance(const Duration(minutes: 11));
        final counts = await Future.wait([service.checkOverdue(), backend().checkOverdue(), backend().checkOverdue()]);
        expect(counts.reduce((a, b) => a + b), 1);
        expect(reports.reports, hasLength(1));
        expect(store.items[walk.id]!.status, WalkStatus.overdue);
        expect(store.items[walk.id]!.reportId, reports.reports.keys.single);
      });

      test('gửi vị trí ngay sau khi backend khác báo quá giờ: không hồi sinh lượt, không báo lặp', () async {
        final walk = await service.start(student, destination: 'Thư viện', minutes: 5);
        clock.advance(const Duration(minutes: 6));
        await backend().checkOverdue();
        await expectLater(
          service.updateLocation(student, walk.id, latitude: 10.8, longitude: 106.7),
          throwsA(apiError('walk_ended')),
        );
        expect(store.items[walk.id]!.status, WalkStatus.overdue);
        expect(await service.checkOverdue(), 0);
        expect(reports.reports, hasLength(1));
      });

      test('vừa gia hạn ở backend khác thì không báo quá giờ', () async {
        final walk = await service.start(student, destination: 'Cổng sau', minutes: 10);
        clock.advance(const Duration(minutes: 9));
        await backend().extend(student, walk.id, 15);
        clock.advance(const Duration(minutes: 2));
        expect(await service.checkOverdue(), 0);
        expect(store.items[walk.id]!.isActive, isTrue);
      });

      test('bấm "đã tới nơi" và backend quét quá giờ cùng lúc: chỉ một bên thắng', () async {
        final walk = await service.start(student, destination: 'Ký túc xá', minutes: 5);
        clock.advance(const Duration(minutes: 6));
        final results = await Future.wait([
          backend().checkOverdue(),
          service.arrive(student, walk.id).then((_) => -1, onError: (Object _) => -2),
        ]);
        final status = store.items[walk.id]!.status;
        if (status == WalkStatus.arrived) {
          expect(results, [0, -1]);
          expect(reports.reports, isEmpty);
        } else {
          expect(status, WalkStatus.overdue);
          expect(results, [1, -2]);
          expect(reports.reports, hasLength(1));
        }
      });
    });

    test('kiểm tra dữ liệu đầu vào', () async {
      await expectLater(
        service.start(student, destination: 'a', minutes: 500),
        throwsA(apiError('validation_failed')),
      );
    });
  });
}

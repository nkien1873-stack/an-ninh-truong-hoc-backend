import 'package:campus_core/campus_core.dart';
import 'package:test/test.dart';

void main() {
  const reporter = Actor(uid: 'r1', role: UserRole.reporter);
  const guard = Actor(uid: 'g1', role: UserRole.guard);
  const otherGuard = Actor(uid: 'g2', role: UserRole.guard);
  const admin = Actor(uid: 'a1', role: UserRole.admin);
  const lockedAdmin = Actor(uid: 'a2', role: UserRole.admin, active: false);

  group('xem báo cáo', () {
    test('người báo chỉ xem báo cáo của mình', () {
      expect(Permissions.canViewReport(reporter, isOwner: true), isTrue);
      expect(Permissions.canViewReport(reporter, isOwner: false), isFalse);
      expect(Permissions.canViewAllReports(reporter), isFalse);
    });
    test('bảo vệ và quản trị xem mọi báo cáo', () {
      expect(Permissions.canViewAllReports(guard), isTrue);
      expect(Permissions.canViewAllReports(admin), isTrue);
      expect(Permissions.canViewReport(guard, isOwner: false), isTrue);
    });
    test('tài khoản bị khoá không xem được gì', () {
      expect(Permissions.canViewAllReports(lockedAdmin), isFalse);
      expect(Permissions.canViewReport(lockedAdmin, isOwner: true), isFalse);
    });
  });

  group('thông tin người báo ẩn danh', () {
    test('bảo vệ không thấy số điện thoại khi ẩn danh', () {
      expect(Permissions.canSeeReporterContact(guard, anonymous: true, isOwner: false), isFalse);
      expect(Permissions.canSeeReporterContact(guard, anonymous: false, isOwner: false), isTrue);
    });
    test('quản trị và chính người báo luôn thấy', () {
      expect(Permissions.canSeeReporterContact(admin, anonymous: true, isOwner: false), isTrue);
      expect(Permissions.canSeeReporterContact(reporter, anonymous: true, isOwner: true), isTrue);
    });
    test('người báo khác không thấy', () {
      expect(Permissions.canSeeReporterContact(reporter, anonymous: false, isOwner: false), isFalse);
    });
  });

  group('đổi trạng thái và phân công', () {
    test('người báo không đổi được trạng thái', () {
      expect(Permissions.canChangeStatus(reporter), isFalse);
    });
    test('bảo vệ đổi được khi chưa giao hoặc giao cho mình', () {
      expect(Permissions.canChangeStatus(guard), isTrue);
      expect(Permissions.canChangeStatus(guard, assigneeUid: 'g1'), isTrue);
      expect(Permissions.canChangeStatus(guard, assigneeUid: 'g2'), isFalse);
    });
    test('quản trị luôn đổi được', () {
      expect(Permissions.canChangeStatus(admin, assigneeUid: 'g2'), isTrue);
    });
    test('bảo vệ chỉ tự nhận việc chưa có người nhận', () {
      expect(Permissions.canAssign(guard, targetUid: 'g1'), isTrue);
      expect(Permissions.canAssign(guard, targetUid: 'g2'), isFalse);
      expect(Permissions.canAssign(otherGuard, targetUid: 'g2', currentAssigneeUid: 'g1'), isFalse);
    });
    test('quản trị giao cho bất kỳ ai', () {
      expect(Permissions.canAssign(admin, targetUid: 'g2', currentAssigneeUid: 'g1'), isTrue);
    });
  });

  group('chức năng quản trị', () {
    test('chỉ quản trị', () {
      for (final check in [
        Permissions.canManageUsers,
        Permissions.canViewStatistics,
        Permissions.canSendTestMessage,
        Permissions.canViewSendLogs,
        Permissions.canEditCampusConfig,
      ]) {
        expect(check(admin), isTrue);
        expect(check(guard), isFalse);
        expect(check(reporter), isFalse);
        expect(check(lockedAdmin), isFalse);
      }
    });
    test('bình luận: người báo của báo cáo và nhân sự an ninh', () {
      expect(Permissions.canComment(reporter, isOwner: true), isTrue);
      expect(Permissions.canComment(reporter, isOwner: false), isFalse);
      expect(Permissions.canComment(guard, isOwner: false), isTrue);
    });
    test('quản trị không tự khoá hoặc tự hạ quyền', () {
      expect(Permissions.validateUserUpdate(admin, targetUid: 'a1', newRole: UserRole.guard), isNotNull);
      expect(Permissions.validateUserUpdate(admin, targetUid: 'a1', newActive: false), isNotNull);
      expect(Permissions.validateUserUpdate(admin, targetUid: 'g1', newActive: false), isNull);
      expect(Permissions.validateUserUpdate(guard, targetUid: 'g2', newActive: false), isNotNull);
    });
    test('trực ca: bảo vệ và quản trị', () {
      expect(Permissions.canToggleOwnDuty(guard), isTrue);
      expect(Permissions.canToggleOwnDuty(reporter), isFalse);
    });
  });
}

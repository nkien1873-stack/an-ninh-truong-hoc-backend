import 'enums.dart';

/// Người đang thao tác.
class Actor {
  const Actor({required this.uid, required this.role, this.active = true});

  final String uid;
  final UserRole role;
  final bool active;

  bool get isAdmin => active && role == UserRole.admin;
  bool get isGuard => active && role == UserRole.guard;
  bool get isStaff => active && role.isStaff;
}

/// Quy tắc phân quyền dùng chung. Backend dùng để chặn thao tác; app dùng để ẩn/hiện nút.
/// Firestore Rules (`firebase/firestore.rules`) áp dụng cùng các quy tắc đọc dữ liệu.
abstract final class Permissions {
  static bool canCreateReport(Actor actor) => actor.active;

  /// Xem danh sách mọi báo cáo (hàng đợi bảo vệ, quản trị).
  static bool canViewAllReports(Actor actor) => actor.isStaff;

  /// Xem một báo cáo cụ thể. [isOwner]: người này là người báo.
  static bool canViewReport(Actor actor, {required bool isOwner}) =>
      actor.active && (actor.role.isStaff || isOwner);

  /// Xem tên và số điện thoại người báo.
  ///
  /// Báo cáo ẩn danh: bảo vệ KHÔNG được thấy. Quản trị được xem (phục vụ xử lý báo cáo sai
  /// sự thật), dữ liệu nằm ở `reports/{id}/private/reporter`, chỉ quản trị đọc được.
  static bool canSeeReporterContact(
    Actor actor, {
    required bool anonymous,
    required bool isOwner,
  }) {
    if (!actor.active) return false;
    if (isOwner || actor.role == UserRole.admin) return true;
    return actor.role == UserRole.guard && !anonymous;
  }

  /// Đổi trạng thái: quản trị luôn được; bảo vệ được khi báo cáo chưa giao ai hoặc giao cho mình.
  static bool canChangeStatus(Actor actor, {String? assigneeUid}) {
    if (actor.isAdmin) return true;
    if (!actor.isGuard) return false;
    return assigneeUid == null || assigneeUid == actor.uid;
  }

  /// Phân công: quản trị giao cho bất kỳ bảo vệ nào; bảo vệ chỉ tự nhận việc chưa có người nhận.
  static bool canAssign(
    Actor actor, {
    required String targetUid,
    String? currentAssigneeUid,
  }) {
    if (actor.isAdmin) return true;
    if (!actor.isGuard) return false;
    return targetUid == actor.uid &&
        (currentAssigneeUid == null || currentAssigneeUid == actor.uid);
  }

  static bool canComment(Actor actor, {required bool isOwner}) =>
      actor.active && (actor.role.isStaff || isOwner);

  static bool canManageUsers(Actor actor) => actor.isAdmin;

  static bool canEditCampusConfig(Actor actor) => actor.isAdmin;

  static bool canViewStatistics(Actor actor) => actor.isAdmin;

  static bool canSendTestMessage(Actor actor) => actor.isAdmin;

  static bool canViewSendLogs(Actor actor) => actor.isAdmin;

  /// Bật/tắt trạng thái đang trực của chính mình.
  static bool canToggleOwnDuty(Actor actor) => actor.isStaff;

  /// Quản trị không được tự hạ quyền hoặc khoá chính mình (tránh mất quyền quản trị cuối cùng).
  static String? validateUserUpdate(
    Actor actor, {
    required String targetUid,
    UserRole? newRole,
    bool? newActive,
  }) {
    if (!actor.isAdmin) return 'Chỉ quản trị được sửa tài khoản.';
    if (targetUid == actor.uid) {
      if (newRole != null && newRole != UserRole.admin) {
        return 'Bạn không thể tự bỏ quyền quản trị của mình.';
      }
      if (newActive == false) return 'Bạn không thể tự khoá tài khoản của mình.';
    }
    return null;
  }
}

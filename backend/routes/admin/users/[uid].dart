import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// PATCH /admin/users/{uid} {role?, active?, onDuty?, displayName?, memberType?, fakeReports?, failedLogins?}.
/// `failedLogins` (0 đến 5) đặt số lần đăng nhập sai: đủ 5 là tạm khoá, ít hơn là mở khoá đăng nhập.
/// `fakeReports` (0 đến ngưỡng) chỉnh số lần báo cáo sai sự thật; đủ ngưỡng thì khoá người báo.
/// Mở khoá thì đặt lại số lần (mặc định 0).
/// DELETE /admin/users/{uid} : xoá tài khoản (báo cáo người đó đã gửi vẫn giữ).
Future<Response> onRequest(RequestContext context, String uid) async {
  ensureMethod(context, {HttpMethod.patch, HttpMethod.delete});
  final services = context.read<AppServices>();
  final admin = context.read<UserRecord>();
  if (context.request.method == HttpMethod.delete) {
    await services.accounts.deleteAccount(admin, uid);
    return Response.json(body: {'ok': true});
  }
  final body = await readJsonObject(context.request);

  final target = await services.users.byId(uid);
  if (target == null) throw ApiException.notFound('Không tìm thấy tài khoản.');

  final roleRaw = optionalString(body, 'role', maxLength: 20);
  final role = roleRaw == null ? null : UserRole.tryFromWire(roleRaw);
  if (roleRaw != null && role == null) throw ApiException.validation({'role': 'Vai trò không hợp lệ.'});
  final active = optionalBool(body, 'active');
  final onDuty = optionalBool(body, 'onDuty');
  final name = optionalString(body, 'displayName', maxLength: ProfileLimits.maxNameLength);
  if (name != null) {
    final error = ProfileLimits.validateDisplayName(name);
    if (error != null) throw ApiException.validation({'displayName': error});
  }
  final memberRaw = optionalString(body, 'memberType', maxLength: 20);
  final memberType = memberRaw == null ? null : MemberType.tryFromWire(memberRaw);
  if (memberRaw != null && memberType == null) {
    throw ApiException.validation({'memberType': 'Đối tượng không hợp lệ.'});
  }

  final denied = Permissions.validateUserUpdate(admin.actor, targetUid: uid, newRole: role, newActive: active);
  if (denied != null) throw ApiException.forbidden(denied);
  // Quản trị gốc (BOOTSTRAP_ADMIN_EMAILS) luôn giữ quyền: không ai khoá hay hạ quyền được.
  if (services.config.bootstrapAdminEmails.contains(target.email) &&
      ((role != null && role != UserRole.admin) || active == false)) {
    throw ApiException.forbidden('Đây là tài khoản quản trị gốc, không thể khoá hay hạ quyền.');
  }
  if (!(role ?? target.role).isStaff && (onDuty ?? false)) {
    throw ApiException.validation({'onDuty': 'Chỉ bảo vệ hoặc quản trị mới có trạng thái trực.'});
  }

  const limit = FakeReportPolicy.lockThreshold;
  var fakeReports = optionalInt(body, 'fakeReports');
  if (fakeReports != null && (fakeReports < 0 || fakeReports > limit)) {
    throw ApiException.validation({'fakeReports': 'Số lần báo sai từ 0 đến $limit.'});
  }
  final unlocking = (active ?? false) && !target.active;
  // Mở khoá thì đếm lại (mặc định từ 0), nếu không lần báo sai kế tiếp sẽ khoá ngay.
  if (unlocking) fakeReports = (fakeReports ?? 0).clamp(0, limit - 1);
  // Quản trị nâng lên đủ ngưỡng thì khoá như khi hệ thống tự đếm.
  final lockForFake = fakeReports != null &&
      fakeReports >= limit &&
      (role ?? target.role) == UserRole.reporter &&
      (active ?? target.active);

  // Đặt số lần đăng nhập sai trước (có kiểm tra), để lỗi không làm lưu dở các thay đổi khác.
  final failedLogins = optionalInt(body, 'failedLogins');
  if (failedLogins != null) await services.accounts.setFailedLogins(uid, failedLogins);

  final updated = await services.users.update(
    uid,
    role: role,
    active: lockForFake ? false : active,
    // Hạ xuống người báo thì tự tắt trực.
    onDuty: (role != null && !role.isStaff) ? false : onDuty,
    displayName: name,
    memberType: memberType,
    fakeReports: fakeReports,
  );
  if (active == false || lockForFake) await services.authTokens.revokeSessions(uid);
  final login = (await services.accounts.loginStatus([uid]))[uid];
  return Response.json(body: {
    'user': {...updated.toApiJson(), ...?login},
  });
}

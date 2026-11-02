import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /me : hồ sơ người đang đăng nhập.
/// PATCH /me {displayName?, phone?, onDuty?} : cập nhật hồ sơ. `phone` rỗng để xoá số. `onDuty` chỉ cho bảo vệ/quản trị.
/// Đối tượng (Sinh viên/Giảng viên...) do quản trị xác nhận qua /admin/users, người dùng không tự đổi.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.get, HttpMethod.patch});
  final user = context.read<UserRecord>();
  if (context.request.method == HttpMethod.get) {
    return Response.json(body: {'user': user.toApiJson()});
  }

  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final name = optionalString(body, 'displayName', label: 'Họ tên', maxLength: ProfileLimits.maxNameLength);
  if (name != null) {
    final error = ProfileLimits.validateDisplayName(name);
    if (error != null) throw ApiException.validation({'displayName': error});
  }
  final phone = readOptionalPhone(body);
  final clearPhone = body.containsKey('phone') && phone == null;
  final memberRaw = optionalString(body, 'memberType', maxLength: 20);
  final memberType = memberRaw == null ? null : MemberType.tryFromWire(memberRaw);
  if (memberRaw != null && memberType == null) {
    throw ApiException.validation({'memberType': 'Đối tượng không hợp lệ.'});
  }
  if (memberType != null && memberType != user.memberType) {
    throw ApiException.forbidden('Đối tượng (Sinh viên/Giảng viên) do quản trị xác nhận. Liên hệ quản trị để đổi.');
  }
  final onDuty = optionalBool(body, 'onDuty');
  if (onDuty != null && !Permissions.canToggleOwnDuty(user.actor)) {
    throw ApiException.forbidden('Chỉ bảo vệ và quản trị mới bật/tắt trạng thái trực.');
  }

  final updated = await services.users.update(
    user.uid,
    displayName: name,
    phone: phone,
    clearPhone: clearPhone,

    onDuty: onDuty,
  );
  return Response.json(body: {'user': updated.toApiJson()});
}

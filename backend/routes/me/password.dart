import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /me/password {currentPassword, newPassword} : đổi mật khẩu khi đang đăng nhập.
/// Các máy khác bị đăng xuất; trả custom token mới cho máy đang dùng.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final body = await readJsonObject(context.request);
  final services = context.read<AppServices>();
  services.limits.check(services.limits.passwordChanges, context.read<UserRecord>().uid, 'đổi mật khẩu');
  String read(String key) => (body[key] is String) ? body[key]! as String : '';
  final result = await services.accounts.changePassword(
    context.read<UserRecord>(),
    read('currentPassword'),
    read('newPassword'),
  );
  return Response.json(body: result.toJson());
}

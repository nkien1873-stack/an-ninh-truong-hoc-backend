import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /auth/password/reset {email, code, password} : nhập đúng OTP thì đặt mật khẩu mới,
/// trả custom token Firebase để đăng nhập luôn.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final result = await services.accounts.resetPassword(
    requireString(body, 'email', label: 'email', maxLength: 254),
    requireString(body, 'code', label: 'mã OTP', maxLength: 10),
    (body['password'] is String) ? body['password']! as String : '',
    ip: clientIp(context, trustProxy: services.config.trustProxy),
  );
  return Response.json(body: result.toJson());
}

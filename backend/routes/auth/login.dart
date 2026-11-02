import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /auth/login {username, password} : `username` là tên đăng nhập hoặc email.
/// Đúng mật khẩu thì trả custom token Firebase.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final result = await services.accounts.login(
    optionalString(body, 'username', label: 'tên đăng nhập', maxLength: 254) ?? '',
    (body['password'] is String) ? body['password']! as String : '',
    ip: clientIp(context, trustProxy: services.config.trustProxy),
  );
  return Response.json(body: result.toJson());
}

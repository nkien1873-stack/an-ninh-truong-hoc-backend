import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /auth/password/forgot {email} : gửi mã OTP đặt lại mật khẩu tới email của tài khoản.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final result = await services.accounts.requestPasswordReset(
    requireString(body, 'email', label: 'email', maxLength: 254),
    ip: clientIp(context, trustProxy: services.config.trustProxy),
  );
  return Response.json(body: result.toJson());
}

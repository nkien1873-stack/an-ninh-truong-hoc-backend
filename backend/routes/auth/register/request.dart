import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /auth/register/request {email, username, password, displayName, memberType, studentId} : kiểm tra thông tin đăng ký
/// (sinh viên bắt buộc MSSV, mỗi MSSV một tài khoản)
/// rồi gửi mã OTP 6 số tới email. Tài khoản chỉ được tạo khi nhập đúng mã (/auth/register/verify).
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final result = await services.accounts.requestRegistration(
    RegistrationInput(
      email: requireString(body, 'email', label: 'email', maxLength: 254),
      username: requireString(body, 'username', label: 'tên đăng nhập', maxLength: 60),
      password: requireString(body, 'password', label: 'mật khẩu', maxLength: 200),
      displayName: requireString(body, 'displayName', label: 'họ tên', maxLength: 120),
      memberType: optionalString(body, 'memberType', maxLength: 20) ?? '',
      studentId: optionalString(body, 'studentId', label: 'MSSV', maxLength: 30) ?? '',
    ),
    ip: clientIp(context, trustProxy: services.config.trustProxy),
  );
  return Response.json(body: result.toJson());
}

import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /auth/register/verify {email, code} : nhập đúng OTP thì tạo tài khoản, trả custom token Firebase.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final result = await services.accounts.verifyRegistration(
    requireString(body, 'email', label: 'email', maxLength: 254),
    requireString(body, 'code', label: 'mã OTP', maxLength: 10),
    ip: clientIp(context, trustProxy: services.config.trustProxy),
  );
  return Response.json(statusCode: HttpStatus.created, body: result.toJson());
}

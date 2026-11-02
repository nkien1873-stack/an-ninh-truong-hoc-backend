import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /me/fcm_token {token} : đăng ký thiết bị nhận push.
/// DELETE /me/fcm_token {token} : huỷ đăng ký (khi đăng xuất).
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post, HttpMethod.delete});
  final services = context.read<AppServices>();
  final user = context.read<UserRecord>();
  final body = await readJsonObject(context.request);
  final token = requireString(body, 'token', label: 'FCM token', maxLength: 4096);
  if (context.request.method == HttpMethod.post) {
    await services.users.addFcmToken(user.uid, token);
  } else {
    await services.users.removeFcmToken(user.uid, token);
  }
  return Response.json(body: {'ok': true});
}

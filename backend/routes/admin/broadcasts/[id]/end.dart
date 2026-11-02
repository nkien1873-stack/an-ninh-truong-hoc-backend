import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /admin/broadcasts/{id}/end : gỡ cảnh báo khỏi banner trước hạn.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  await services.broadcasts.end(context.read<UserRecord>(), id);
  return Response.json(body: {'ok': true});
}

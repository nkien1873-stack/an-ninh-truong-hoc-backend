import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /walks/{id}/cancel : huỷ lượt đi (không báo bảo vệ).
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final walk = await context.read<AppServices>().walks.cancel(context.read<UserRecord>(), id);
  return Response.json(body: {'walk': walk.toApiJson()});
}

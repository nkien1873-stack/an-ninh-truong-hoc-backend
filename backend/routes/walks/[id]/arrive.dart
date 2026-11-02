import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /walks/{id}/arrive : xác nhận đã tới nơi an toàn.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final walk = await context.read<AppServices>().walks.arrive(context.read<UserRecord>(), id);
  return Response.json(body: {'walk': walk.toApiJson()});
}

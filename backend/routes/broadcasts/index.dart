import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /broadcasts : 20 cảnh báo toàn trường gần nhất (kể cả đã gỡ), mới nhất trước.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.get});
  final broadcasts = await context.read<AppServices>().broadcasts.recent();
  return Response.json(body: {'broadcasts': [for (final b in broadcasts) b.toApiJson()]});
}

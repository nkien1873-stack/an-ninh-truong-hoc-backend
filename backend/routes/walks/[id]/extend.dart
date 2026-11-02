import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /walks/{id}/extend {minutes} : thêm thời gian trước khi tự báo bảo vệ.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final body = await readJsonObject(context.request);
  final walk = await context.read<AppServices>().walks.extend(
        context.read<UserRecord>(),
        id,
        optionalInt(body, 'minutes') ?? 5,
      );
  return Response.json(body: {'walk': walk.toApiJson()});
}

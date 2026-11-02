import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /reports/{id}/assign {assigneeUid} : quản trị phân công, hoặc bảo vệ tự nhận việc.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final user = context.read<UserRecord>();
  final body = await readJsonObject(context.request);
  final target = requireString(body, 'assigneeUid', label: 'người nhận việc', maxLength: 128);
  final report = await services.reportService.assign(user, id, target);
  return Response.json(body: {'report': report.toApiJson()});
}

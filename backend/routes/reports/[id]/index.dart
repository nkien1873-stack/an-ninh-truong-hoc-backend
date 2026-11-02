import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /reports/{id} : báo cáo, lịch sử xử lý và người báo (nếu người xem được phép).
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.get});
  final detail = await context.read<AppServices>().reportService.detail(context.read<UserRecord>(), id);
  return Response.json(body: detail.toApiJson());
}

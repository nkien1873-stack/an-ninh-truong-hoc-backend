import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /config : thông tin công khai (tên trường, số trực, danh sách khu vực).
/// Không cần đăng nhập để màn đăng nhập vẫn hiện nút "Gọi trực an ninh".
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.get});
  final services = context.read<AppServices>();
  final campus = await services.currentCampusConfig();
  return Response.json(body: {
    ...campus.toJson(),
    'otpMode': services.accounts.otpMode,
  });
}

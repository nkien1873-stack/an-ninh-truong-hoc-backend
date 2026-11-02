import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /walks/{id}/sos {latitude?, longitude?, accuracy?} : khẩn cấp trong lúc đi, tạo báo cáo ngay.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final body = await readJsonObject(context.request);
  final walk = await context.read<AppServices>().walks.sos(
        context.read<UserRecord>(),
        id,
        latitude: optionalDouble(body, 'latitude'),
        longitude: optionalDouble(body, 'longitude'),
        accuracy: optionalDouble(body, 'accuracy'),
      );
  return Response.json(body: {'walk': walk.toApiJson()});
}

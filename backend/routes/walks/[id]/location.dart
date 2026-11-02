import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /walks/{id}/location {latitude, longitude, accuracy?} : cập nhật vị trí trong lúc đi.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);
  final lat = optionalDouble(body, 'latitude');
  final lng = optionalDouble(body, 'longitude');
  if (lat == null || lng == null) throw ApiException.validation({'location': 'Thiếu toạ độ GPS.'});
  final walk = await services.walks.updateLocation(
    context.read<UserRecord>(),
    id,
    latitude: lat,
    longitude: lng,
    accuracy: optionalDouble(body, 'accuracy'),
  );
  return Response.json(body: {'walk': walk.toApiJson()});
}

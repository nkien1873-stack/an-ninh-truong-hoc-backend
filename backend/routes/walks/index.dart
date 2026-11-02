import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /walks?scope=mine|active : lượt đang đi của mình, hoặc mọi lượt (bảo vệ, quản trị).
/// POST /walks {destination, minutes, latitude?, longitude?, accuracy?} : bắt đầu "Đi cùng tôi".
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.get, HttpMethod.post});
  final services = context.read<AppServices>();
  if (context.request.method == HttpMethod.get) {
    final user = context.read<UserRecord>();
    if (context.request.uri.queryParameters['scope'] == 'active') {
      if (!user.role.isStaff) throw ApiException.forbidden();
      final walks = await services.walks.listActive();
      return Response.json(body: {'walks': [for (final w in walks) w.toDetailJson()]});
    }
    return Response.json(body: {'walk': (await services.walks.activeFor(user.uid))?.toDetailJson()});
  }
  final body = await readJsonObject(context.request);
  services.limits.check(services.limits.walks, context.read<UserRecord>().uid, 'bắt đầu Đi cùng tôi');
  final walk = await services.walks.start(
    context.read<UserRecord>(),
    destination: requireString(body, 'destination', label: 'nơi đến', maxLength: 200),
    minutes: optionalInt(body, 'minutes') ?? 15,
    latitude: optionalDouble(body, 'latitude'),
    longitude: optionalDouble(body, 'longitude'),
    accuracy: optionalDouble(body, 'accuracy'),
  );
  return Response.json(statusCode: HttpStatus.created, body: {'walk': walk.toApiJson()});
}

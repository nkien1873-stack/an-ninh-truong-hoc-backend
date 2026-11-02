import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /admin/broadcasts {title, body, level, hours?} : gửi cảnh báo toàn trường (banner trong app
/// + push tới mọi tài khoản). Danh sách cảnh báo ở `GET /broadcasts`.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final admin = context.read<UserRecord>();
  final body = await readJsonObject(context.request);
  services.limits.check(services.limits.broadcasts, admin.uid, 'gửi cảnh báo toàn trường');
  final level = BroadcastLevel.tryFromWire(requireString(body, 'level', label: 'mức độ', maxLength: 20));
  if (level == null) throw ApiException.validation({'level': 'Mức độ không hợp lệ.'});
  final (record, delivered) = await services.broadcasts.send(
    admin,
    title: requireString(body, 'title', label: 'tiêu đề', maxLength: 200),
    body: requireString(body, 'body', label: 'nội dung', maxLength: 1000),
    level: level,
    hours: optionalInt(body, 'hours') ?? 12,
  );
  return Response.json(
    statusCode: HttpStatus.created,
    body: {'broadcast': record.toApiJson(), 'pushDelivered': delivered},
  );
}

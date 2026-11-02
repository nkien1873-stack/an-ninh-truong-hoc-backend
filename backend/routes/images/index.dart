import 'dart:convert';
import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /images {data: `JPEG base64`} : tải ảnh sự cố lên (cần đăng nhập), trả `{path}` để gắn vào
/// báo cáo. Ảnh lưu trong MongoDB.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.post});
  return await requireAuth()(_upload)(context);
}

Future<Response> _upload(RequestContext context) async {
  final services = context.read<AppServices>();
  services.limits.check(services.limits.images, context.read<UserRecord>().uid, 'tải ảnh');
  // Ảnh tối đa 700 KB, base64 khoảng 940 KB: cho phép body tới 1,2 MB.
  final raw = await readBody(context.request, maxBytes: 1200 * 1024, tooLarge: 'Ảnh quá lớn.');
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    throw ApiException.badRequest('Dữ liệu gửi lên không phải JSON hợp lệ.');
  }
  final data = json is Map ? json['data'] : null;
  if (data is! String) throw ApiException.validation({'image': 'Thiếu dữ liệu ảnh.'});
  final path = await services.images.upload(context.read<UserRecord>(), data);
  return Response.json(statusCode: HttpStatus.created, body: {'path': path});
}

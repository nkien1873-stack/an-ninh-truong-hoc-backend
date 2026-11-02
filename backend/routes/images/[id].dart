import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /images/{id} : ảnh JPEG. ID ngẫu nhiên 32 ký tự đóng vai trò khoá xem ảnh (xem [ImageService]).
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.get});
  final bytes = await context.read<AppServices>().images.load(id.replaceAll('.jpg', ''));
  if (bytes == null) throw ApiException.notFound('Không tìm thấy ảnh.');
  return Response.bytes(
    body: bytes,
    headers: {
      HttpHeaders.contentTypeHeader: 'image/jpeg',
      HttpHeaders.cacheControlHeader: 'private, max-age=86400, immutable',
    },
  );
}

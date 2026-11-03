import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET / : app và health check của Render nhận JSON; mở bằng trình duyệt thì hiện trang giới thiệu.
Future<Response> onRequest(RequestContext context) async {
  final accept = context.request.headers[HttpHeaders.acceptHeader] ?? '';
  if (!accept.contains('text/html')) {
    return Response.json(body: {'ok': true, 'service': 'campus_safety_backend'});
  }
  final services = context.read<AppServices>();
  final dbOk = await services.databaseHealthy();
  final campus = dbOk ? (await services.currentCampusConfig()).campusName : '';
  return Response(
    body: landingPageHtml(databaseOk: dbOk, campusName: campus),
    headers: {HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8'},
  );
}

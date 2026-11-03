import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// GET /health : máy chủ và MongoDB Atlas có hoạt động không. CSDL không trả lời thì báo 503.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.get});
  final services = context.read<AppServices>();
  final dbOk = await services.databaseHealthy();
  return Response.json(
    statusCode: dbOk ? HttpStatus.ok : HttpStatus.serviceUnavailable,
    body: {
      'ok': dbOk,
      'service': 'campus_safety_backend',
      'database': dbOk ? 'connected' : 'unreachable',
      'time': DateTime.now().toUtc().toIso8601String(),
    },
  );
}

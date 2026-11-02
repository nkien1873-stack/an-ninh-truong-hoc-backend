import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /reports/{id}/comments {text} : trao đổi giữa người báo và bảo vệ/quản trị.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final user = context.read<UserRecord>();
  final body = await readJsonObject(context.request);
  final text = requireString(body, 'text', label: 'nội dung', maxLength: ReportLimits.maxCommentLength);
  services.limits.check(services.limits.comments, user.uid, 'gửi tin nhắn');
  await services.reportService.comment(user, id, text);
  return Response.json(statusCode: HttpStatus.created, body: {'ok': true});
}

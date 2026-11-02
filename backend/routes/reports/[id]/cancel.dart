import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /reports/{id}/cancel {reason?} : người báo tự huỷ khi bảo vệ chưa bắt đầu xử lý.
/// Báo cáo vẫn lưu (trạng thái "Đã huỷ"); báo cho bảo vệ đang giữ hoặc đang trực.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final user = context.read<UserRecord>();
  final body = await readJsonObject(context.request);
  final reason = optionalString(body, 'reason', label: 'Lý do', maxLength: ReportStatusMachine.maxCancelReasonLength);
  final report = await services.reportService.cancel(user, id, reason: reason);
  return Response.json(body: {'report': report.toApiJson()});
}

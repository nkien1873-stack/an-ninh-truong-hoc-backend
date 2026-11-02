import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// POST /reports/{id}/status {status, note?, fake?} : bảo vệ/quản trị cập nhật trạng thái.
/// `fake: true` khi từ chối vì báo cáo sai sự thật. Gửi thông báo đẩy cho người báo.
Future<Response> onRequest(RequestContext context, String id) async {
  ensureMethod(context, {HttpMethod.post});
  final services = context.read<AppServices>();
  final user = context.read<UserRecord>();
  if (!user.role.isStaff) throw ApiException.forbidden('Chỉ bảo vệ hoặc quản trị được cập nhật trạng thái.');
  final body = await readJsonObject(context.request);
  final status = ReportStatus.tryFromWire(requireString(body, 'status', label: 'trạng thái', maxLength: 20));
  if (status == null) throw ApiException.validation({'status': 'Trạng thái không hợp lệ.'});
  final note = optionalString(body, 'note', label: 'Ghi chú', maxLength: ReportStatusMachine.maxNoteLength);

  final report = await services.reportService.changeStatus(
    user,
    id,
    to: status,
    note: note,
    fake: optionalBool(body, 'fake') ?? false,
  );
  return Response.json(body: {'report': report.toApiJson()});
}

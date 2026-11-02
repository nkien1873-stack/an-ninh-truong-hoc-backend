import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// PUT /admin/config {campusName, hotline, buildings[]} : cấu hình trường.
Future<Response> onRequest(RequestContext context) async {
  ensureMethod(context, {HttpMethod.put});
  final services = context.read<AppServices>();
  final body = await readJsonObject(context.request);

  final campusName = requireString(body, 'campusName', label: 'tên trường', maxLength: 120);
  final hotline = optionalString(body, 'hotline', label: 'Số trực', maxLength: 20);
  if (hotline != null && hotline.isNotEmpty && !RegExp(r'^[0-9+ ().-]{3,20}$').hasMatch(hotline)) {
    throw ApiException.validation({'hotline': 'Số trực chỉ gồm chữ số, dấu cách, +, -, (, ).'});
  }
  final rawBuildings = body['buildings'];
  if (rawBuildings is! List) throw ApiException.validation({'buildings': 'Danh sách khu vực không hợp lệ.'});
  final buildings = <String>[];
  for (final b in rawBuildings) {
    if (b is! String) continue;
    final name = b.trim();
    if (name.isEmpty || buildings.contains(name)) continue;
    if (name.length > 60) throw ApiException.validation({'buildings': 'Tên khu vực tối đa 60 ký tự: "$name".'});
    buildings.add(name);
  }
  if (buildings.isEmpty) throw ApiException.validation({'buildings': 'Cần ít nhất một khu vực.'});
  if (buildings.length > 100) throw ApiException.validation({'buildings': 'Tối đa 100 khu vực.'});

  final saved = await services.campusConfig.write(CampusConfig(
    campusName: campusName,
    hotline: (hotline?.isEmpty ?? true) ? null : hotline,
    buildings: buildings,
    updatedAt: DateTime.now().toUtc(),
  ));
  return Response.json(body: saved.toJson());
}

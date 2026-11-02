import 'dart:math';

import 'enums.dart';

/// Giới hạn dữ liệu báo cáo, dùng chung cho form trong app và kiểm tra ở backend.
abstract final class ReportLimits {
  static const int minDescriptionLength = 10;
  static const int maxDescriptionLength = 2000;
  static const int maxEmergencyNoteLength = 500;
  static const int maxBuildingLength = 60;
  static const int maxFloorLength = 20;
  static const int maxRoomLength = 30;
  static const int maxImages = 5;
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const int maxCommentLength = 1000;

  /// Cho phép lệch đồng hồ máy người dùng tối đa 5 phút về tương lai.
  static const Duration futureTolerance = Duration(minutes: 5);
  static const Duration maxAge = Duration(days: 30);

  /// Đường dẫn ảnh do app tải lên: `report_images/<id>.jpg` (ảnh lưu trong Firestore qua backend),
  /// hoặc `incident_images/yyyyMM/<id>.jpg` (Firebase Storage, khi project có bật Storage).
  static final RegExp imagePathPattern = RegExp(
    r'^(incident_images/\d{6}/[A-Za-z0-9_-]{8,64}\.(jpg|png|webp)|report_images/[A-Za-z0-9_-]{24,64}\.jpg)$',
  );

  /// Ảnh lưu trong Firestore: tối đa 700 KB sau khi nén (giới hạn 1 MB mỗi tài liệu, base64 tăng ~33%).
  static const int maxStoredImageBytes = 700 * 1024;
}

/// Dữ liệu một báo cáo do người dùng gửi lên (body của `POST /reports`).
class ReportDraft {
  const ReportDraft({
    required this.type,
    required this.severity,
    required this.description,
    required this.occurredAt,
    this.building,
    this.floor,
    this.room,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.anonymous = false,
    this.emergency = false,
    this.imagePaths = const [],
  });

  final IncidentType type;
  final Severity severity;
  final String description;
  final DateTime occurredAt;
  final String? building;
  final String? floor;
  final String? room;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final bool anonymous;
  final bool emergency;
  final List<String> imagePaths;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Báo cáo khẩn cấp luôn ở mức "Khẩn cấp".
  Severity get effectiveSeverity => emergency ? Severity.critical : severity;

  String get locationText => formatLocation(building: building, floor: floor, room: room);

  Map<String, Object?> toJson() => {
        'type': type.wire,
        'severity': severity.wire,
        'description': description,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'building': building,
        'floor': floor,
        'room': room,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'anonymous': anonymous,
        'emergency': emergency,
        'imagePaths': imagePaths,
      };

  /// Đọc từ JSON. Ném [FormatException] nếu sai kiểu dữ liệu.
  factory ReportDraft.fromJson(Map<String, Object?> json) {
    final type = IncidentType.tryFromWire(json['type'] as String?);
    if (type == null) throw const FormatException('type');
    final severity = Severity.tryFromWire(json['severity'] as String?);
    if (severity == null) throw const FormatException('severity');
    final occurredRaw = json['occurredAt'];
    final occurredAt = occurredRaw is String ? DateTime.tryParse(occurredRaw) : null;
    if (occurredAt == null) throw const FormatException('occurredAt');
    final images = json['imagePaths'];
    return ReportDraft(
      type: type,
      severity: severity,
      description: (json['description'] as String?) ?? '',
      occurredAt: occurredAt,
      building: _cleanOptional(json['building']),
      floor: _cleanOptional(json['floor']),
      room: _cleanOptional(json['room']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      accuracyMeters: (json['accuracyMeters'] as num?)?.toDouble(),
      anonymous: json['anonymous'] == true,
      emergency: json['emergency'] == true,
      imagePaths: images is List ? images.whereType<String>().toList() : const [],
    );
  }

  static String? _cleanOptional(Object? value) {
    if (value is! String) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
}

/// Kiểm tra [ReportDraft]. Trả về map `tên trường -> lỗi tiếng Việt`; map rỗng nghĩa là hợp lệ.
Map<String, String> validateReportDraft(ReportDraft d, {DateTime? now}) {
  final errors = <String, String>{};
  final current = (now ?? DateTime.now()).toUtc();
  final description = d.description.trim();

  if (d.emergency) {
    if (description.length > ReportLimits.maxEmergencyNoteLength) {
      errors['description'] = 'Ghi chú khẩn cấp tối đa ${ReportLimits.maxEmergencyNoteLength} ký tự.';
    }
  } else if (description.length < ReportLimits.minDescriptionLength) {
    errors['description'] =
        'Mô tả ít nhất ${ReportLimits.minDescriptionLength} ký tự để bảo vệ hiểu sự việc.';
  } else if (description.length > ReportLimits.maxDescriptionLength) {
    errors['description'] = 'Mô tả tối đa ${ReportLimits.maxDescriptionLength} ký tự.';
  }

  final building = d.building?.trim() ?? '';
  if (building.isEmpty) {
    if (!d.emergency) {
      errors['building'] = 'Chọn toà nhà hoặc khu vực xảy ra sự cố.';
    } else if (!d.hasCoordinates) {
      errors['building'] = 'Chưa có vị trí GPS. Hãy chọn toà nhà hoặc khu vực.';
    }
  } else if (building.length > ReportLimits.maxBuildingLength) {
    errors['building'] = 'Tên toà nhà tối đa ${ReportLimits.maxBuildingLength} ký tự.';
  }
  if ((d.floor?.length ?? 0) > ReportLimits.maxFloorLength) {
    errors['floor'] = 'Tầng tối đa ${ReportLimits.maxFloorLength} ký tự.';
  }
  if ((d.room?.length ?? 0) > ReportLimits.maxRoomLength) {
    errors['room'] = 'Phòng tối đa ${ReportLimits.maxRoomLength} ký tự.';
  }

  if ((d.latitude == null) != (d.longitude == null)) {
    errors['location'] = 'Toạ độ GPS không đầy đủ.';
  } else if (d.hasCoordinates) {
    final lat = d.latitude!, lng = d.longitude!;
    if (lat.isNaN || lng.isNaN || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      errors['location'] = 'Toạ độ GPS không hợp lệ.';
    }
  }
  if (d.accuracyMeters != null && (d.accuracyMeters!.isNaN || d.accuracyMeters! < 0)) {
    errors['location'] = 'Độ chính xác GPS không hợp lệ.';
  }

  final occurred = d.occurredAt.toUtc();
  if (occurred.isAfter(current.add(ReportLimits.futureTolerance))) {
    errors['occurredAt'] = 'Thời gian xảy ra không được ở tương lai.';
  } else if (occurred.isBefore(current.subtract(ReportLimits.maxAge))) {
    errors['occurredAt'] = 'Chỉ nhận sự cố xảy ra trong 30 ngày gần đây.';
  }

  if (d.imagePaths.length > ReportLimits.maxImages) {
    errors['images'] = 'Tối đa ${ReportLimits.maxImages} ảnh.';
  } else if (d.imagePaths.any((p) => !ReportLimits.imagePathPattern.hasMatch(p))) {
    errors['images'] = 'Đường dẫn ảnh không hợp lệ.';
  } else if (d.imagePaths.toSet().length != d.imagePaths.length) {
    errors['images'] = 'Có ảnh bị trùng.';
  }
  return errors;
}

/// Kiểm tra nội dung bình luận. Trả về lỗi tiếng Việt hoặc `null`.
String? validateComment(String? text) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return 'Nhập nội dung trao đổi.';
  if (t.length > ReportLimits.maxCommentLength) {
    return 'Tối đa ${ReportLimits.maxCommentLength} ký tự.';
  }
  return null;
}

/// Ghép vị trí thành một dòng: `Toà A2, tầng 3, phòng 305`.
String formatLocation({String? building, String? floor, String? room}) {
  final parts = <String>[
    if (building != null && building.trim().isNotEmpty) building.trim(),
    if (floor != null && floor.trim().isNotEmpty) 'tầng ${floor.trim()}',
    if (room != null && room.trim().isNotEmpty) 'phòng ${room.trim()}',
  ];
  return parts.isEmpty ? 'Chưa rõ vị trí' : parts.join(', ');
}

/// Bộ ký tự cho mã sự cố, bỏ các ký tự dễ nhầm (0/O, 1/I/L).
const String _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/// Tạo mã sự cố dễ đọc qua điện thoại: `SC-261019-K7Q4`.
/// Ngày lấy theo giờ Việt Nam (UTC+7).
String generateReportCode({DateTime? now, Random? random}) {
  final vn = toVietnamTime(now ?? DateTime.now());
  final rnd = random ?? Random.secure();
  final yy = (vn.year % 100).toString().padLeft(2, '0');
  final mm = vn.month.toString().padLeft(2, '0');
  final dd = vn.day.toString().padLeft(2, '0');
  final suffix = List.generate(4, (_) => _codeAlphabet[rnd.nextInt(_codeAlphabet.length)]).join();
  return 'SC-$yy$mm$dd-$suffix';
}

final RegExp reportCodePattern = RegExp(r'^SC-\d{6}-[A-Z0-9]{4}$');

/// Việt Nam dùng UTC+7 quanh năm, không có giờ mùa hè.
DateTime toVietnamTime(DateTime t) {
  final utc = t.toUtc().add(const Duration(hours: 7));
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
}

/// Định dạng `14:05 19/10/2026` theo giờ Việt Nam (16 ký tự).
String formatVietnamDateTime(DateTime t) {
  final vn = toVietnamTime(t);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(vn.hour)}:${two(vn.minute)} ${two(vn.day)}/${two(vn.month)}/${vn.year}';
}

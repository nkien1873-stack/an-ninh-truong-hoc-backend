import 'package:campus_core/campus_core.dart';

/// Hồ sơ người dùng (collection `users`).
class UserRecord {
  const UserRecord({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.memberType,
    required this.active,
    required this.onDuty,
    this.phone,
    this.username,
    this.studentId,
    this.fakeReports = 0,
    this.fcmTokens = const [],
    this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
  });

  final String uid;

  /// Email đăng nhập (nhận OTP), mỗi email một tài khoản.
  final EmailAddress email;

  /// Số điện thoại liên hệ (tuỳ chọn), để bảo vệ gọi lại khi cần.
  final VietnamPhone? phone;

  /// Tên đăng nhập (đã chuẩn hoá). `null` với tài khoản quản trị tạo trước mà chưa đăng ký.
  final String? username;

  /// Mã số sinh viên (chỉ sinh viên), mỗi MSSV một tài khoản.
  final String? studentId;

  /// Số báo cáo bị đánh dấu sai sự thật ([FakeReportPolicy]).
  final int fakeReports;
  final String displayName;
  final UserRole role;
  final MemberType memberType;
  final bool active;

  /// Bảo vệ đang trực.
  final bool onDuty;
  final List<String> fcmTokens;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastLoginAt;

  Actor get actor => Actor(uid: uid, role: role, active: active);

  bool get profileComplete => displayName.trim().isNotEmpty;

  /// Tên dùng trong tin nhắn khi người dùng chưa nhập tên.
  String get greetingName => profileComplete ? displayName : 'bạn';

  UserRecord copyWith({
    String? displayName,
    VietnamPhone? phone,
    bool clearPhone = false,
    String? username,
    String? studentId,
    int? fakeReports,
    UserRole? role,
    MemberType? memberType,
    bool? active,
    bool? onDuty,
    List<String>? fcmTokens,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) =>
      UserRecord(
        uid: uid,
        email: email,
        phone: clearPhone ? null : (phone ?? this.phone),
        username: username ?? this.username,
        studentId: studentId ?? this.studentId,
        fakeReports: fakeReports ?? this.fakeReports,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        memberType: memberType ?? this.memberType,
        active: active ?? this.active,
        onDuty: onDuty ?? this.onDuty,
        fcmTokens: fcmTokens ?? this.fcmTokens,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      );

  Map<String, Object?> toApiJson() => {
        'uid': uid,
        'email': email.value,
        'username': username,
        'studentId': studentId,
        'fakeReports': fakeReports,
        'phone': phone?.local,
        'displayName': displayName,
        'role': role.wire,
        'memberType': memberType.wire,
        'active': active,
        'onDuty': onDuty,
        'profileComplete': profileComplete,
      };
}

/// Báo cáo sự cố. Với báo cáo ẩn danh, các trường người báo để trống; thông tin thật nằm ở
/// [ReporterPrivate].
class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.code,
    required this.type,
    required this.severity,
    required this.status,
    required this.description,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    required this.emergency,
    required this.anonymous,
    this.building,
    this.floor,
    this.room,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.reporterUid,
    this.reporterName,
    this.reporterPhone,
    this.reporterMemberType,
    this.imagePaths = const [],
    this.assigneeUid,
    this.assigneeName,
    this.lastNote,
    this.closedAt,
    this.fake = false,
  });

  final String id;
  final String code;
  final IncidentType type;
  final Severity severity;
  final ReportStatus status;
  final String description;
  final DateTime occurredAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool emergency;
  final bool anonymous;
  final String? building;
  final String? floor;
  final String? room;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? reporterUid;
  final String? reporterName;
  final String? reporterPhone;
  final MemberType? reporterMemberType;
  final List<String> imagePaths;
  final String? assigneeUid;
  final String? assigneeName;
  final String? lastNote;
  final DateTime? closedAt;

  /// Bị bảo vệ/quản trị đánh dấu là báo cáo sai sự thật khi từ chối.
  final bool fake;

  String get locationText => formatLocation(building: building, floor: floor, room: room);

  ReportRecord copyWith({
    ReportStatus? status,
    DateTime? updatedAt,
    String? assigneeUid,
    String? assigneeName,
    String? lastNote,
    DateTime? closedAt,
    bool? fake,
    bool clearClosedAt = false,
    bool clearLastNote = false,
  }) =>
      ReportRecord(
        id: id,
        code: code,
        type: type,
        severity: severity,
        status: status ?? this.status,
        description: description,
        occurredAt: occurredAt,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        emergency: emergency,
        anonymous: anonymous,
        building: building,
        floor: floor,
        room: room,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        reporterUid: reporterUid,
        reporterName: reporterName,
        reporterPhone: reporterPhone,
        reporterMemberType: reporterMemberType,
        imagePaths: imagePaths,
        assigneeUid: assigneeUid ?? this.assigneeUid,
        assigneeName: assigneeName ?? this.assigneeName,
        lastNote: clearLastNote ? null : (lastNote ?? this.lastNote),
        closedAt: clearClosedAt ? null : (closedAt ?? this.closedAt),
        fake: fake ?? this.fake,
      );

  Map<String, Object?> toApiJson() => {
        'id': id,
        'code': code,
        'status': status.wire,
        'severity': severity.wire,
        'type': type.wire,
        'emergency': emergency,
        'fake': fake,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  /// Đầy đủ các trường để app hiển thị. Không chứa người báo thật của báo cáo ẩn danh.
  Map<String, Object?> toDetailJson() => {
        ...toApiJson(),
        'description': description,
        'occurredAt': occurredAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'anonymous': anonymous,
        'locationText': locationText,
        'building': building,
        'floor': floor,
        'room': room,
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracyMeters,
        'reporterUid': anonymous ? null : reporterUid,
        'reporterName': anonymous ? null : reporterName,
        'reporterPhone': anonymous ? null : reporterPhone,
        'reporterMemberType': anonymous ? null : reporterMemberType?.wire,
        'imagePaths': imagePaths,
        'assigneeUid': assigneeUid,
        'assigneeName': assigneeName,
        'lastNote': lastNote,
        'closedAt': closedAt?.toUtc().toIso8601String(),
      };
}

/// Thông tin thật của người báo, chỉ quản trị và chính người báo đọc được.
class ReporterPrivate {
  const ReporterPrivate({required this.uid, required this.displayName, this.email, this.phone});

  final String uid;
  final String displayName;
  final EmailAddress? email;

  /// Số liên hệ của người báo, có thể trống.
  final VietnamPhone? phone;

  Map<String, Object?> toApiJson() => {'uid': uid, 'phoneLocal': phone?.local, 'displayName': displayName};
}

/// Người đang xử lý báo cáo, để người báo gọi hoặc nhắn khi bảo vệ đã nhận (như tài xế đã nhận chuyến).
class AssigneeContact {
  const AssigneeContact({required this.uid, required this.displayName, this.phone});

  final String uid;
  final String displayName;
  final VietnamPhone? phone;

  Map<String, Object?> toApiJson() => {'uid': uid, 'displayName': displayName, 'phoneLocal': phone?.local};
}

/// Một dòng lịch sử của báo cáo.
class ReportEvent {
  const ReportEvent({
    required this.type,
    required this.createdAt,
    required this.actorName,
    required this.actorRole,
    this.actorUid,
    this.fromStatus,
    this.toStatus,
    this.note,
  });

  final ReportEventType type;
  final DateTime createdAt;
  final String actorName;
  final UserRole actorRole;

  /// Bỏ trống khi người báo ẩn danh.
  final String? actorUid;
  final ReportStatus? fromStatus;
  final ReportStatus? toStatus;
  final String? note;

  Map<String, Object?> toApiJson() => {
        'type': type.wire,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'actorUid': actorUid,
        'actorName': actorName,
        'actorRole': actorRole.wire,
        'fromStatus': fromStatus?.wire,
        'toStatus': toStatus?.wire,
        'note': note,
      };
}

/// Cấu hình trường (collection `config`, tài liệu `app`).
class CampusConfig {
  const CampusConfig({
    required this.campusName,
    required this.hotline,
    required this.buildings,
    this.updatedAt,
  });

  final String campusName;
  final String? hotline;
  final List<String> buildings;
  final DateTime? updatedAt;

  Map<String, Object?> toJson() => {
        'campusName': campusName,
        'hotline': hotline,
        'buildings': buildings,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };
}

/// Phiên OTP của một email (collection `otp_challenges`, khoá băm), API không trả về.
class OtpChallenge {
  const OtpChallenge({
    this.codeHash,
    this.salt,
    this.expiresAt,
    this.attempts = 0,
    this.sendTimes = const [],
    this.pending = const {},
  });

  final String? codeHash;
  final String? salt;
  final DateTime? expiresAt;
  final int attempts;

  /// Thời điểm các lần gửi trong 24 giờ gần nhất (để giới hạn tần suất).
  final List<DateTime> sendTimes;

  /// Thông tin đăng ký đang chờ xác nhận (tên đăng nhập, họ tên, mật khẩu đã băm).
  final Map<String, String> pending;

  bool get hasActiveCode => codeHash != null && salt != null && expiresAt != null;

  DateTime? get lastSentAt => sendTimes.isEmpty ? null : sendTimes.reduce((a, b) => a.isAfter(b) ? a : b);

  OtpChallenge copyWith({
    String? codeHash,
    String? salt,
    DateTime? expiresAt,
    int? attempts,
    List<DateTime>? sendTimes,
    Map<String, String>? pending,
    bool clearCode = false,
  }) =>
      OtpChallenge(
        codeHash: clearCode ? null : (codeHash ?? this.codeHash),
        salt: clearCode ? null : (salt ?? this.salt),
        expiresAt: clearCode ? null : (expiresAt ?? this.expiresAt),
        attempts: attempts ?? this.attempts,
        sendTimes: sendTimes ?? this.sendTimes,
        pending: clearCode ? const {} : (pending ?? this.pending),
      );
}

/// Các giá trị liệt kê dùng chung. Mỗi enum có [wire] (giá trị lưu Firestore / gửi API)
/// và [label] (nhãn tiếng Việt hiển thị).
library;

T _fromWire<T extends Enum>(List<T> values, String? wire, String Function(T) wireOf, T fallback) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  return fallback;
}

T? _tryFromWire<T extends Enum>(List<T> values, String? wire, String Function(T) wireOf) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  return null;
}

enum UserRole {
  reporter('reporter', 'Người báo'),
  guard('guard', 'Bảo vệ'),
  admin('admin', 'Quản trị');

  const UserRole(this.wire, this.label);

  final String wire;
  final String label;

  bool get isStaff => this == guard || this == admin;

  static UserRole fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, UserRole.reporter);

  static UserRole? tryFromWire(String? wire) =>
      _tryFromWire(values, wire, (v) => v.wire);
}

/// Đối tượng của người báo trong trường.
enum MemberType {
  student('student', 'Sinh viên'),
  lecturer('lecturer', 'Giảng viên'),
  staff('staff', 'Nhân viên'),
  other('other', 'Khác');

  const MemberType(this.wire, this.label);

  final String wire;
  final String label;

  /// Đối tượng người dùng được tự chọn khi đăng ký / sửa hồ sơ. Các loại khác (Nhân viên, Khác)
  /// chỉ quản trị gán.
  static const selfSelectable = [MemberType.student, MemberType.lecturer];

  bool get isSelfSelectable => selfSelectable.contains(this);

  static MemberType fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, MemberType.other);

  static MemberType? tryFromWire(String? wire) =>
      _tryFromWire(values, wire, (v) => v.wire);
}

enum IncidentType {
  theft('theft', 'Trộm cắp'),
  fight('fight', 'Đánh nhau'),
  fire('fire', 'Cháy nổ'),
  suspicious('suspicious', 'Người lạ khả nghi'),
  damage('damage', 'Hư hỏng thiết bị'),
  other('other', 'Khác');

  const IncidentType(this.wire, this.label);

  final String wire;
  final String label;

  static IncidentType fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, IncidentType.other);

  static IncidentType? tryFromWire(String? wire) =>
      _tryFromWire(values, wire, (v) => v.wire);
}

enum Severity {
  low('low', 'Thấp', 0),
  medium('medium', 'Trung bình', 1),
  high('high', 'Cao', 2),
  critical('critical', 'Khẩn cấp', 3);

  const Severity(this.wire, this.label, this.rank);

  final String wire;
  final String label;

  /// Dùng để sắp xếp: số càng lớn càng gấp.
  final int rank;

  static Severity fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, Severity.medium);

  static Severity? tryFromWire(String? wire) =>
      _tryFromWire(values, wire, (v) => v.wire);
}

enum ReportStatus {
  submitted('submitted', 'Đã gửi'),
  received('received', 'Đã tiếp nhận'),
  inProgress('in_progress', 'Đang xử lý'),
  resolved('resolved', 'Đã giải quyết'),
  rejected('rejected', 'Từ chối'),

  /// Người báo tự huỷ trước khi bảo vệ bắt đầu xử lý. Báo cáo vẫn được lưu để tra cứu.
  cancelled('cancelled', 'Đã huỷ');

  const ReportStatus(this.wire, this.label);

  final String wire;
  final String label;

  bool get isClosed => this == resolved || this == rejected || this == cancelled;
  bool get isOpen => !isClosed;

  static ReportStatus fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, ReportStatus.submitted);

  static ReportStatus? tryFromWire(String? wire) =>
      _tryFromWire(values, wire, (v) => v.wire);
}

/// Loại sự kiện trong lịch sử của một báo cáo.
enum ReportEventType {
  created('created'),
  status('status'),
  assigned('assigned'),
  comment('comment');

  const ReportEventType(this.wire);

  final String wire;

  static ReportEventType fromWire(String? wire) =>
      _fromWire(values, wire, (v) => v.wire, ReportEventType.comment);
}

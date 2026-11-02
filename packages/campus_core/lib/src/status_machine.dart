import 'enums.dart';

/// Vòng đời một báo cáo:
///
/// ```
/// Đã gửi ─► Đã tiếp nhận ─► Đang xử lý ─► Đã giải quyết
///    │            │              │
///    └────────────┴──────────────┴──► Từ chối
/// ```
///
/// Bảo vệ có thể bỏ qua bước "Đã tiếp nhận" (nhận và xử lý ngay). Chỉ quản trị được mở lại
/// một báo cáo đã giải quyết hoặc từ chối. Người báo tự huỷ được khi báo cáo còn "Đã gửi" hoặc
/// "Đã tiếp nhận" ([canCancel]); báo cáo đã huỷ không mở lại.
abstract final class ReportStatusMachine {
  static const Map<ReportStatus, Set<ReportStatus>> _staffTransitions = {
    ReportStatus.submitted: {
      ReportStatus.received,
      ReportStatus.inProgress,
      ReportStatus.rejected,
    },
    ReportStatus.received: {
      ReportStatus.inProgress,
      ReportStatus.resolved,
      ReportStatus.rejected,
    },
    ReportStatus.inProgress: {
      ReportStatus.resolved,
      ReportStatus.rejected,
    },
    ReportStatus.resolved: {},
    ReportStatus.rejected: {},
    ReportStatus.cancelled: {},
  };

  /// Người báo được tự huỷ khi bảo vệ chưa bắt đầu xử lý (giống huỷ chuyến trước khi tài xế tới).
  static bool canCancel(ReportStatus from) => from == ReportStatus.submitted || from == ReportStatus.received;

  /// Lý do huỷ, tối đa.
  static const int maxCancelReasonLength = 200;

  static const Map<ReportStatus, Set<ReportStatus>> _adminReopen = {
    ReportStatus.resolved: {ReportStatus.inProgress},
    ReportStatus.rejected: {ReportStatus.received},
  };

  /// Độ dài tối thiểu của lý do khi từ chối.
  static const int minRejectReasonLength = 5;

  /// Độ dài tối đa của ghi chú kèm thay đổi trạng thái.
  static const int maxNoteLength = 500;

  /// Các trạng thái mà [role] được phép chuyển tới từ [from].
  static Set<ReportStatus> nextStatuses(ReportStatus from, UserRole role) {
    if (!role.isStaff) return const {};
    return {
      ...?_staffTransitions[from],
      if (role == UserRole.admin) ...?_adminReopen[from],
    };
  }

  static bool canTransition(ReportStatus from, ReportStatus to, UserRole role) =>
      nextStatuses(from, role).contains(to);

  /// Trả về thông báo lỗi tiếng Việt nếu chuyển trạng thái không hợp lệ, `null` nếu hợp lệ.
  static String? validate({
    required ReportStatus from,
    required ReportStatus to,
    required UserRole role,
    String? note,
  }) {
    if (!role.isStaff) {
      return 'Chỉ bảo vệ hoặc quản trị được cập nhật trạng thái.';
    }
    if (from == to) {
      return 'Báo cáo đang ở trạng thái "${to.label}".';
    }
    if (!canTransition(from, to, role)) {
      if (from.isClosed && role != UserRole.admin) {
        return 'Báo cáo đã đóng. Chỉ quản trị được mở lại.';
      }
      return 'Không thể chuyển từ "${from.label}" sang "${to.label}".';
    }
    final trimmed = note?.trim() ?? '';
    if (trimmed.length > maxNoteLength) {
      return 'Ghi chú tối đa $maxNoteLength ký tự.';
    }
    if (to == ReportStatus.rejected && trimmed.length < minRejectReasonLength) {
      return 'Hãy ghi lý do từ chối (ít nhất $minRejectReasonLength ký tự).';
    }
    return null;
  }

  /// Nhãn hành động cho nút chuyển sang [to].
  static String actionLabel(ReportStatus from, ReportStatus to) {
    if (from.isClosed) return 'Mở lại';
    return switch (to) {
      ReportStatus.received => 'Tiếp nhận',
      ReportStatus.inProgress => 'Bắt đầu xử lý',
      ReportStatus.resolved => 'Đánh dấu đã giải quyết',
      ReportStatus.rejected => 'Từ chối',
      ReportStatus.submitted => 'Đặt lại',
      ReportStatus.cancelled => 'Huỷ báo cáo',
    };
  }
}

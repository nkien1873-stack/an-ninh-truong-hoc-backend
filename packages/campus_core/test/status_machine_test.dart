import 'package:campus_core/campus_core.dart';
import 'package:test/test.dart';

void main() {
  group('ReportStatusMachine', () {
    test('luồng chuẩn của bảo vệ', () {
      expect(ReportStatusMachine.canTransition(ReportStatus.submitted, ReportStatus.received, UserRole.guard), isTrue);
      expect(ReportStatusMachine.canTransition(ReportStatus.received, ReportStatus.inProgress, UserRole.guard), isTrue);
      expect(ReportStatusMachine.canTransition(ReportStatus.inProgress, ReportStatus.resolved, UserRole.guard), isTrue);
    });

    test('bảo vệ có thể xử lý ngay không cần tiếp nhận', () {
      expect(ReportStatusMachine.canTransition(ReportStatus.submitted, ReportStatus.inProgress, UserRole.guard), isTrue);
    });

    test('không nhảy thẳng từ Đã gửi sang Đã giải quyết', () {
      expect(ReportStatusMachine.canTransition(ReportStatus.submitted, ReportStatus.resolved, UserRole.admin), isFalse);
    });

    test('người báo không đổi được trạng thái', () {
      expect(ReportStatusMachine.nextStatuses(ReportStatus.submitted, UserRole.reporter), isEmpty);
      expect(
        ReportStatusMachine.validate(from: ReportStatus.submitted, to: ReportStatus.received, role: UserRole.reporter),
        isNotNull,
      );
    });

    test('chỉ quản trị mở lại báo cáo đã đóng', () {
      expect(ReportStatusMachine.nextStatuses(ReportStatus.resolved, UserRole.guard), isEmpty);
      expect(ReportStatusMachine.nextStatuses(ReportStatus.resolved, UserRole.admin), {ReportStatus.inProgress});
      expect(ReportStatusMachine.nextStatuses(ReportStatus.rejected, UserRole.admin), {ReportStatus.received});
      expect(
        ReportStatusMachine.validate(from: ReportStatus.resolved, to: ReportStatus.inProgress, role: UserRole.guard),
        'Báo cáo đã đóng. Chỉ quản trị được mở lại.',
      );
    });

    test('từ chối phải có lý do', () {
      expect(
        ReportStatusMachine.validate(from: ReportStatus.received, to: ReportStatus.rejected, role: UserRole.guard),
        isNotNull,
      );
      expect(
        ReportStatusMachine.validate(
          from: ReportStatus.received,
          to: ReportStatus.rejected,
          role: UserRole.guard,
          note: 'Báo cáo trùng với SC-261019-K7Q4',
        ),
        isNull,
      );
    });

    test('không chuyển sang chính trạng thái hiện tại', () {
      expect(
        ReportStatusMachine.validate(from: ReportStatus.received, to: ReportStatus.received, role: UserRole.admin),
        isNotNull,
      );
    });

    test('ghi chú quá dài', () {
      expect(
        ReportStatusMachine.validate(
          from: ReportStatus.received,
          to: ReportStatus.inProgress,
          role: UserRole.guard,
          note: 'x' * 501,
        ),
        isNotNull,
      );
    });

    test('nhãn hành động', () {
      expect(ReportStatusMachine.actionLabel(ReportStatus.submitted, ReportStatus.received), 'Tiếp nhận');
      expect(ReportStatusMachine.actionLabel(ReportStatus.resolved, ReportStatus.inProgress), 'Mở lại');
    });

    test('người báo huỷ được trước khi bảo vệ bắt đầu xử lý; đã huỷ là đóng hẳn', () {
      expect(ReportStatusMachine.canCancel(ReportStatus.submitted), isTrue);
      expect(ReportStatusMachine.canCancel(ReportStatus.received), isTrue);
      expect(ReportStatusMachine.canCancel(ReportStatus.inProgress), isFalse);
      expect(ReportStatusMachine.canCancel(ReportStatus.cancelled), isFalse);
      expect(ReportStatus.cancelled.isClosed, isTrue);
      expect(ReportStatusMachine.nextStatuses(ReportStatus.cancelled, UserRole.admin), isEmpty);
      expect(ReportStatus.fromWire('cancelled'), ReportStatus.cancelled);
    });
  });

  test('wire của trạng thái khớp Firestore', () {
    expect(ReportStatus.inProgress.wire, 'in_progress');
    expect(ReportStatus.fromWire('in_progress'), ReportStatus.inProgress);
    expect(ReportStatus.fromWire('???'), ReportStatus.submitted);
    expect(ReportStatus.tryFromWire('???'), isNull);
  });
}

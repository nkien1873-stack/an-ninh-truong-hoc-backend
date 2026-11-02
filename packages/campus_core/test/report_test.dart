import 'dart:math';

import 'package:campus_core/campus_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 19, 7, 30);

  ReportDraft draft({
    String description = 'Có người lạ lục lọi xe máy ở bãi xe B',
    String? building = 'Toà B1',
    bool emergency = false,
    double? lat,
    double? lng,
    DateTime? occurredAt,
    List<String> images = const [],
  }) =>
      ReportDraft(
        type: IncidentType.suspicious,
        severity: Severity.medium,
        description: description,
        occurredAt: occurredAt ?? now.subtract(const Duration(minutes: 10)),
        building: building,
        latitude: lat,
        longitude: lng,
        emergency: emergency,
        imagePaths: images,
      );

  group('validateReportDraft', () {
    test('báo cáo đầy đủ là hợp lệ', () {
      expect(validateReportDraft(draft(), now: now), isEmpty);
    });

    test('mô tả quá ngắn', () {
      expect(validateReportDraft(draft(description: 'trộm'), now: now), contains('description'));
    });

    test('thiếu toà nhà khi báo thường', () {
      expect(validateReportDraft(draft(building: null), now: now), contains('building'));
    });

    test('khẩn cấp: không cần mô tả, có GPS là đủ', () {
      final d = draft(description: '', building: null, emergency: true, lat: 21.0, lng: 105.8);
      expect(validateReportDraft(d, now: now), isEmpty);
      expect(d.effectiveSeverity, Severity.critical);
    });

    test('khẩn cấp: không GPS và không toà nhà thì báo lỗi', () {
      final d = draft(description: '', building: null, emergency: true);
      expect(validateReportDraft(d, now: now), contains('building'));
    });

    test('toạ độ thiếu hoặc sai', () {
      expect(validateReportDraft(draft(lat: 21.0), now: now), contains('location'));
      expect(validateReportDraft(draft(lat: 200, lng: 105), now: now), contains('location'));
    });

    test('thời gian ở tương lai hoặc quá cũ', () {
      expect(
        validateReportDraft(draft(occurredAt: now.add(const Duration(hours: 1))), now: now),
        contains('occurredAt'),
      );
      expect(
        validateReportDraft(draft(occurredAt: now.add(const Duration(minutes: 3))), now: now),
        isEmpty,
        reason: 'cho phép lệch đồng hồ 5 phút',
      );
      expect(
        validateReportDraft(draft(occurredAt: now.subtract(const Duration(days: 31))), now: now),
        contains('occurredAt'),
      );
    });

    test('ảnh: tối đa 5, đúng đường dẫn, không trùng', () {
      const ok = 'incident_images/202610/abcDEF12_3456.jpg';
      expect(validateReportDraft(draft(images: [ok]), now: now), isEmpty);
      expect(
        validateReportDraft(draft(images: List.generate(6, (i) => 'incident_images/202610/abcdefgh$i.jpg')), now: now),
        contains('images'),
      );
      expect(validateReportDraft(draft(images: ['../etc/passwd']), now: now), contains('images'));
      const stored = 'report_images/AbCdEfGhIjKlMnOpQrStUvWx1234.jpg';
      expect(validateReportDraft(draft(images: [stored]), now: now), isEmpty);
      expect(validateReportDraft(draft(images: ['report_images/ngan.jpg']), now: now), contains('images'));
      expect(validateReportDraft(draft(images: [ok, ok]), now: now), contains('images'));
    });
  });

  test('ReportDraft JSON hai chiều', () {
    final d = draft(lat: 21.03, lng: 105.85, images: ['incident_images/202610/abcdefgh.jpg']);
    final back = ReportDraft.fromJson(d.toJson());
    expect(back.type, d.type);
    expect(back.severity, d.severity);
    expect(back.latitude, 21.03);
    expect(back.imagePaths, d.imagePaths);
    expect(back.occurredAt.isAtSameMomentAs(d.occurredAt), isTrue);
  });

  test('ReportDraft.fromJson từ chối loại sự cố lạ', () {
    expect(
      () => ReportDraft.fromJson({'type': 'alien', 'severity': 'low', 'occurredAt': now.toIso8601String()}),
      throwsFormatException,
    );
  });

  test('formatLocation', () {
    expect(formatLocation(building: 'Toà A2', floor: '3', room: '305'), 'Toà A2, tầng 3, phòng 305');
    expect(formatLocation(building: 'Thư viện'), 'Thư viện');
    expect(formatLocation(), 'Chưa rõ vị trí');
  });

  test('generateReportCode theo ngày Việt Nam', () {
    // 18:00 UTC ngày 18/10 là 01:00 ngày 19/10 giờ Việt Nam.
    final code = generateReportCode(now: DateTime.utc(2026, 10, 18, 18), random: Random(1));
    expect(code, startsWith('SC-261019-'));
    expect(reportCodePattern.hasMatch(code), isTrue);
    expect(code.length, lessThanOrEqualTo(30));
  });

  test('formatVietnamDateTime dài 16 ký tự', () {
    final s = formatVietnamDateTime(DateTime.utc(2026, 10, 19, 7, 5));
    expect(s, '14:05 19/10/2026');
    expect(s.length, lessThanOrEqualTo(20));
  });

  test('validateComment', () {
    expect(validateComment('  '), isNotNull);
    expect(validateComment('Đã thấy, đang tới'), isNull);
    expect(validateComment('a' * 1001), isNotNull);
  });
}

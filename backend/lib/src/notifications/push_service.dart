import 'dart:io';

import 'package:dart_firebase_admin/messaging.dart' as fcm;

class PushMessage {
  const PushMessage({
    required this.title,
    required this.body,
    this.data = const {},
    this.urgent = false,
  });

  final String title;
  final String body;

  /// Dữ liệu cho app điều hướng khi bấm thông báo, ví dụ `{type: report, reportId: ...}`.
  final Map<String, String> data;

  /// Dùng kênh "Cảnh báo sự cố" mức ưu tiên cao (bảo vệ trực).
  final bool urgent;
}

class PushResult {
  const PushResult({this.successCount = 0, this.failureCount = 0, this.invalidTokens = const []});

  final int successCount;
  final int failureCount;

  /// Token đã hết hiệu lực, cần xoá khỏi hồ sơ người dùng.
  final List<String> invalidTokens;
}

abstract interface class PushService {
  Future<PushResult> sendToTokens(List<String> tokens, PushMessage message);
}

/// Gửi push qua Firebase Cloud Messaging (HTTP v1) bằng dart_firebase_admin.
class FcmPushService implements PushService {
  FcmPushService(this._messaging);

  final fcm.Messaging _messaging;

  /// Phải trùng với kênh tạo trong app (`lib/core/notifications/local_notifications.dart`).
  static const urgentChannelId = 'incident_alerts';
  static const defaultChannelId = 'report_updates';

  static const _invalidCodes = {
    'messaging/registration-token-not-registered',
    'messaging/invalid-registration-token',
  };

  /// Thư viện admin hay gộp lỗi HTTP của FCM thành `internal-error`, nên phải xem cả nội dung lỗi.
  static bool isDeadToken(String code, String message) =>
      _invalidCodes.contains(code) ||
      message.contains('NotRegistered') ||
      message.contains('not a valid FCM registration token');

  @override
  Future<PushResult> sendToTokens(List<String> tokens, PushMessage message) async {
    final unique = tokens.toSet().where((t) => t.isNotEmpty).toList();
    if (unique.isEmpty) return const PushResult();
    var ok = 0, failed = 0;
    final invalid = <String>[];
    for (var i = 0; i < unique.length; i += 500) {
      final chunk = unique.sublist(i, i + 500 > unique.length ? unique.length : i + 500);
      try {
        final batch = await _messaging.sendEachForMulticast(
          fcm.MulticastMessage(
            tokens: chunk,
            data: message.data,
            notification: fcm.Notification(title: message.title, body: message.body),
            android: fcm.AndroidConfig(
              priority: message.urgent ? fcm.AndroidConfigPriority.high : fcm.AndroidConfigPriority.normal,
              notification: fcm.AndroidNotification(
                channelId: message.urgent ? urgentChannelId : defaultChannelId,
              ),
            ),
          ),
        );
        ok += batch.successCount;
        failed += batch.failureCount;
        for (var j = 0; j < batch.responses.length; j++) {
          final error = batch.responses[j].error;
          if (error != null && isDeadToken(error.code, error.message)) invalid.add(chunk[j]);
        }
      } on Object catch (e) {
        failed += chunk.length;
        stderr.writeln('[fcm] Gửi push thất bại: $e');
      }
    }
    return PushResult(successCount: ok, failureCount: failed, invalidTokens: invalid);
  }
}

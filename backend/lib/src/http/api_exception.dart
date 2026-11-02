import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Lỗi trả về cho app dưới dạng `{"error": {"code", "message", "details"}}`.
/// [message] luôn là tiếng Việt, hiển thị trực tiếp cho người dùng.
class ApiException implements Exception {
  ApiException(this.statusCode, this.code, this.message, {this.details, this.retryAfter});

  ApiException.badRequest(String message, {String code = 'bad_request', Map<String, Object?>? details})
      : this(HttpStatus.badRequest, code, message, details: details);

  ApiException.validation(Map<String, String> fieldErrors)
      : this(
          HttpStatus.unprocessableEntity,
          'validation_failed',
          fieldErrors.values.first,
          details: {'fields': fieldErrors},
        );

  ApiException.unauthorized([String message = 'Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.'])
      : this(HttpStatus.unauthorized, 'unauthorized', message);

  ApiException.forbidden([String message = 'Bạn không có quyền thực hiện thao tác này.'])
      : this(HttpStatus.forbidden, 'forbidden', message);

  ApiException.notFound([String message = 'Không tìm thấy dữ liệu.'])
      : this(HttpStatus.notFound, 'not_found', message);

  ApiException.conflict(String message, {String code = 'conflict'})
      : this(HttpStatus.conflict, code, message);

  ApiException.tooManyRequests(String message, {Duration? retryAfter, String code = 'rate_limited'})
      : this(HttpStatus.tooManyRequests, code, message, retryAfter: retryAfter);

  ApiException.methodNotAllowed()
      : this(HttpStatus.methodNotAllowed, 'method_not_allowed', 'Phương thức không được hỗ trợ.');

  final int statusCode;
  final String code;
  final String message;
  final Map<String, Object?>? details;
  final Duration? retryAfter;

  Response toResponse() => Response.json(
        statusCode: statusCode,
        headers: {
          if (retryAfter != null) HttpHeaders.retryAfterHeader: '${retryAfter!.inSeconds.clamp(1, 86400)}',
        },
        body: {
          'error': {
            'code': code,
            'message': message,
            if (details != null) 'details': details,
            if (retryAfter != null) 'retryAfterSeconds': retryAfter!.inSeconds.clamp(1, 86400),
          },
        },
      );

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Nói "x phút" / "x giây" bằng tiếng Việt.
String humanizeWait(Duration d) {
  if (d.inMinutes >= 60) return '${(d.inMinutes / 60).ceil()} giờ';
  if (d.inSeconds > 90) return '${(d.inSeconds / 60).ceil()} phút';
  return '${d.inSeconds.clamp(1, 90)} giây';
}

import 'dart:io';

import 'package:campus_core/campus_core.dart';
import 'package:dart_frog/dart_frog.dart';

import '../app_services.dart';
import '../auth/firebase_auth_service.dart';
import '../data/models.dart';
import 'api_exception.dart';

/// Bắt [ApiException] và lỗi bất ngờ, trả JSON thống nhất. Không lộ stack trace cho client.
Middleware errorHandler() {
  return (handler) {
    return (context) async {
      try {
        return await handler(context);
      } on ApiException catch (e) {
        return e.toResponse();
      } on Object catch (e, st) {
        stderr
          ..writeln('[error] ${context.request.method.value} ${context.request.uri.path}: $e')
          ..writeln(st);
        return ApiException(
          HttpStatus.internalServerError,
          'internal_error',
          'Máy chủ gặp lỗi. Vui lòng thử lại sau ít phút.',
        ).toResponse();
      }
    };
  };
}

/// Yêu cầu Firebase ID token hợp lệ (`Authorization: Bearer <token>`) và tài khoản đang hoạt
/// động. Cung cấp [UserRecord] cho handler qua `context.read<UserRecord>()`.
Middleware requireAuth({Set<UserRole>? roles}) {
  return (handler) {
    return (context) async {
      final services = context.read<AppServices>();
      final header = context.request.headers[HttpHeaders.authorizationHeader] ?? '';
      if (!header.startsWith('Bearer ') || header.length < 20) {
        throw ApiException.unauthorized('Bạn cần đăng nhập để tiếp tục.');
      }
      final String uid;
      try {
        uid = await services.authTokens.verifyIdToken(header.substring(7).trim());
      } on InvalidIdTokenException {
        throw ApiException.unauthorized();
      } on AuthUnavailableException catch (e) {
        stderr.writeln('[auth] Không kiểm tra được phiên đăng nhập: $e');
        throw ApiException(
          HttpStatus.serviceUnavailable,
          'auth_unavailable',
          'Máy chủ tạm thời không kiểm tra được phiên đăng nhập. Kiểm tra Internet của máy chạy backend rồi thử lại.',
        );
      }
      final user = await services.users.byId(uid);
      if (user == null) {
        throw ApiException.unauthorized('Không tìm thấy tài khoản. Hãy đăng nhập lại.');
      }
      if (!user.active) {
        throw ApiException.forbidden('Tài khoản đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
      }
      if (roles != null && !roles.contains(user.role)) {
        throw ApiException.forbidden();
      }
      return handler(context.provide<UserRecord>(() => user));
    };
  };
}

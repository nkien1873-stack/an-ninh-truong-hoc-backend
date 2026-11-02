import 'package:dart_firebase_admin/auth.dart' as admin;

abstract interface class AuthTokenService {
  /// Tạo custom token để app gọi `FirebaseAuth.signInWithCustomToken`.
  Future<String> createCustomToken(String uid, {Map<String, Object?>? claims});

  /// Kiểm tra Firebase ID token gửi kèm header `Authorization: Bearer ...`.
  /// Trả về uid, ném [InvalidIdTokenException] nếu token sai hoặc hết hạn.
  Future<String> verifyIdToken(String idToken);

  /// Thu hồi phiên đăng nhập (khi khoá tài khoản).
  Future<void> revokeSessions(String uid);

  /// Xoá tài khoản Firebase Auth (khi quản trị xoá tài khoản). Không lỗi nếu chưa từng đăng nhập.
  Future<void> deleteUser(String uid);
}

class InvalidIdTokenException implements Exception {
  InvalidIdTokenException(this.reason);

  final String reason;

  @override
  String toString() => 'InvalidIdTokenException: $reason';
}

/// Không kiểm tra được token vì mất kết nối tới Firebase Auth (không phải token sai).
class AuthUnavailableException implements Exception {
  AuthUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'AuthUnavailableException: $reason';
}

class FirebaseAuthTokenService implements AuthTokenService {
  FirebaseAuthTokenService(this._auth);

  final admin.Auth _auth;

  @override
  Future<String> createCustomToken(String uid, {Map<String, Object?>? claims}) =>
      _auth.createCustomToken(uid, developerClaims: claims);

  @override
  Future<String> verifyIdToken(String idToken) async {
    try {
      // checkRevoked: phiên cũ bị thu hồi (đặt lại mật khẩu, khoá, xoá tài khoản) bị từ chối ngay,
      // không đợi ID token hết hạn sau 1 giờ.
      final decoded = await _auth.verifyIdToken(idToken, checkRevoked: true);
      return decoded.uid;
    } on admin.FirebaseAuthAdminException catch (e) {
      if (e.errorCode == admin.AuthClientErrorCode.internalError) throw AuthUnavailableException(e.toString());
      throw InvalidIdTokenException(e.toString());
    } on Object catch (e) {
      // SocketException, ClientException, hết giờ...: mạng chập chờn, không đăng xuất người dùng.
      throw AuthUnavailableException(e.toString());
    }
  }

  @override
  Future<void> revokeSessions(String uid) async {
    try {
      await _auth.revokeRefreshTokens(uid);
    } on Object {
      // Người dùng có thể chưa từng đăng nhập Firebase Auth (tài khoản tạo trước).
    }
  }

  @override
  Future<void> deleteUser(String uid) async {
    try {
      await _auth.deleteUser(uid);
    } on Object {
      // Chưa từng đăng nhập thì không có tài khoản Auth để xoá.
    }
  }
}

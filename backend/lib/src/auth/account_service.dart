import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campus_core/campus_core.dart';
import 'package:crypto/crypto.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import '../http/api_exception.dart';
import 'firebase_auth_service.dart';
import 'ip_rate_limiter.dart';
import 'otp_mailer.dart';
import 'password_hasher.dart';

/// Kết quả gửi mã xác nhận đăng ký.
class OtpRequestResult {
  const OtpRequestResult({
    required this.email,
    required this.expiresIn,
    required this.resendAfter,
    required this.mode,
  });

  final EmailAddress email;
  final Duration expiresIn;
  final Duration resendAfter;
  final String mode;

  Map<String, Object?> toJson() => {
        'email': email.value,
        'emailMasked': email.masked,
        'expiresInSeconds': expiresIn.inSeconds,
        'resendAfterSeconds': resendAfter.inSeconds,
        'mode': mode,
      };
}

/// Đăng nhập thành công: custom token Firebase để app đăng nhập.
class SignInResult {
  const SignInResult({required this.customToken, required this.user, required this.isNewUser});

  final String customToken;
  final UserRecord user;
  final bool isNewUser;

  Map<String, Object?> toJson() => {
        'customToken': customToken,
        'user': user.toApiJson(),
        'isNewUser': isNewUser,
      };
}

/// Thông tin người dùng nhập ở màn đăng ký.
class RegistrationInput {
  const RegistrationInput({
    required this.email,
    required this.username,
    required this.password,
    required this.displayName,
    required this.memberType,
    this.studentId = '',
  });

  final String email;
  final String username;
  final String password;
  final String displayName;

  /// Người đăng ký tự chọn, chỉ Sinh viên hoặc Giảng viên ([MemberType.selfSelectable]).
  final String memberType;

  /// Mã số sinh viên, bắt buộc khi là Sinh viên ([StudentIdPolicy]).
  final String studentId;
}

/// Tài khoản: **đăng ký** bằng email + mã OTP gửi qua email, **đăng nhập** bằng tên đăng nhập
/// (hoặc email) + mật khẩu.
///
/// - OTP 6 số từ `Random.secure()`, hết hạn 5 phút, chỉ lưu HMAC-SHA256(pepper, email + mã + salt);
///   khoá tài liệu cũng là HMAC của email. Sai 5 lần khoá mã. Giới hạn gửi theo email
///   (60 giây giữa 2 lần, 5 lần/giờ, 10 lần/ngày) và theo IP.
/// - Thông tin đăng ký (tên đăng nhập, họ tên, mật khẩu đã băm) chờ trong phiên OTP; tài khoản
///   chỉ được tạo khi nhập đúng mã.
/// - Mật khẩu băm PBKDF2-HMAC-SHA256. Sai 5 lần liên tiếp khoá đăng nhập 15 phút; giới hạn theo IP.
/// - Email đã có tài khoản nhưng chưa có mật khẩu (quản trị tạo trước) được "nhận" tài khoản đó
///   khi đăng ký, giữ nguyên vai trò.
class AccountService {
  AccountService({
    required OtpStore store,
    required UserRepository users,
    required CredentialRepository credentials,
    required OtpMailer mailer,
    required AuthTokenService auth,
    required String pepper,
    required bool allowSelfRegistration,
    required Set<EmailAddress> bootstrapAdmins,
    PasswordHasher? hasher,
    SlidingWindowRateLimiter? ipSendLimiter,
    SlidingWindowRateLimiter? ipVerifyLimiter,
    SlidingWindowRateLimiter? ipLoginLimiter,
    DateTime Function()? clock,
    Random? random,
  })  : _store = store,
        _users = users,
        _credentials = credentials,
        _mailer = mailer,
        _auth = auth,
        _pepper = utf8.encode(pepper),
        _allowSelfRegistration = allowSelfRegistration,
        _bootstrapAdmins = bootstrapAdmins,
        _hasher = hasher ?? PasswordHasher(),
        _clock = clock ?? DateTime.now,
        _random = random ?? Random.secure(),
        _ipSend = ipSendLimiter ?? SlidingWindowRateLimiter(maxEvents: 10, window: const Duration(minutes: 15), clock: clock),
        _ipVerify = ipVerifyLimiter ?? SlidingWindowRateLimiter(maxEvents: 30, window: const Duration(minutes: 15), clock: clock),
        _ipLogin = ipLoginLimiter ?? SlidingWindowRateLimiter(maxEvents: 30, window: const Duration(minutes: 15), clock: clock);

  final OtpStore _store;
  final UserRepository _users;
  final CredentialRepository _credentials;
  final OtpMailer _mailer;
  final AuthTokenService _auth;
  final List<int> _pepper;
  final bool _allowSelfRegistration;
  final Set<EmailAddress> _bootstrapAdmins;
  final PasswordHasher _hasher;
  final DateTime Function() _clock;
  final Random _random;
  final SlidingWindowRateLimiter _ipSend;
  final SlidingWindowRateLimiter _ipVerify;
  final SlidingWindowRateLimiter _ipLogin;

  static const _invalidLogin = 'Tên đăng nhập hoặc mật khẩu không đúng.';

  /// Kênh gửi mã hiển thị cho app.
  String get otpMode => _mailer.mode;

  String challengeKey(EmailAddress email) =>
      Hmac(sha256, _pepper).convert(utf8.encode('otp-key:${email.value}')).toString();

  String hashCode6(EmailAddress email, String code, String salt) =>
      Hmac(sha256, _pepper).convert(utf8.encode('${email.value}:$code:$salt')).toString();

  // ---------------------------------------------------------------- Đăng ký

  /// Kiểm tra thông tin đăng ký rồi gửi mã OTP tới email. Chưa tạo tài khoản.
  Future<OtpRequestResult> requestRegistration(RegistrationInput input, {required String ip}) async {
    final email = _parseEmail(input.email);
    final username = UsernamePolicy.normalize(input.username);
    final name = input.displayName.trim();
    // Mặc định Sinh viên; nếu app gửi lựa chọn thì chỉ nhận Sinh viên/Giảng viên.
    final memberType = input.memberType.isEmpty ? MemberType.student : MemberType.tryFromWire(input.memberType);
    final existing = await _users.byEmail(email);
    // Tài khoản quản trị tạo trước (bảo vệ, giảng viên) giữ đối tượng đã gán nên không cần MSSV.
    final isStudent = (existing?.memberType ?? memberType) == MemberType.student;
    final studentId = StudentIdPolicy.normalize(input.studentId);
    final errors = <String, String>{
      if (memberType == null || !memberType.isSelfSelectable) 'memberType': 'Chọn Sinh viên hoặc Giảng viên.',
      if (isStudent) 'studentId': ?StudentIdPolicy.validate(studentId),
      'username': ?UsernamePolicy.validate(username),
      'password': ?PasswordPolicy.validate(input.password),
      'displayName': ?ProfileLimits.validateDisplayName(name),
    };
    if (errors.isNotEmpty) throw ApiException.validation(errors);

    if (existing != null) {
      if (!existing.active) {
        throw ApiException.forbidden('Tài khoản của email này đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
      }
      if (await _credentials.byUid(existing.uid) != null) {
        throw ApiException.conflict('Email này đã được đăng ký. Hãy đăng nhập.', code: 'email_registered');
      }
    } else if (!_allowSelfRegistration && !_bootstrapAdmins.contains(email)) {
      throw ApiException.forbidden(
        'Email này chưa được cấp quyền dùng ứng dụng. Liên hệ phòng bảo vệ hoặc quản trị.',
      );
    }
    if (await _credentials.usernameTaken(username)) {
      throw ApiException.validation({'username': 'Tên đăng nhập này đã có người dùng. Chọn tên khác.'});
    }
    if (isStudent && await _studentIdTaken(studentId, exceptUid: existing?.uid)) {
      throw ApiException.validation({'studentId': _studentIdTakenMessage});
    }

    // Chặn trước khi băm: băm mật khẩu tốn CPU, không để gửi hàng loạt làm nghẽn máy chủ.
    _limitSends(ip);
    return _sendCode(
      email,
      action: 'đăng ký tài khoản',
      pending: {
        'purpose': 'register',
        'username': username,
        'displayName': name,
        'memberType': memberType!.wire,
        if (isStudent) 'studentId': studentId,
        'passwordHash': await _hasher.hashAsync(input.password),
      },
    );
  }

  static const _studentIdTakenMessage = 'MSSV này đã có tài khoản. Mỗi MSSV chỉ đăng ký một tài khoản.';

  Future<bool> _studentIdTaken(String studentId, {String? exceptUid}) async {
    final owner = await _users.byStudentId(studentId);
    return owner != null && owner.uid != exceptUid;
  }

  /// Nhập đúng mã thì tạo tài khoản (hoặc nhận tài khoản quản trị tạo trước) và đăng nhập luôn.
  Future<SignInResult> verifyRegistration(String rawEmail, String rawCode, {required String ip}) async {
    final email = _parseEmail(rawEmail);
    final pending = await _checkCode(email, rawCode, ip: ip, purpose: 'register');
    final username = pending['username'];
    final passwordHash = pending['passwordHash'];
    final name = pending['displayName'] ?? '';
    if (username == null || passwordHash == null) {
      throw ApiException.badRequest('Phiên đăng ký đã hết. Hãy đăng ký lại.', code: 'registration_missing');
    }

    final isBootstrapAdmin = _bootstrapAdmins.contains(email);
    var (user, created) = await _users.getOrCreate(
      email,
      role: isBootstrapAdmin ? UserRole.admin : UserRole.reporter,
    );
    if (!user.active) {
      throw ApiException.forbidden('Tài khoản này đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
    }
    final studentId = pending['studentId'];
    // Người khác có thể đã dùng MSSV này trong lúc chờ nhập mã.
    if (studentId != null && await _studentIdTaken(studentId, exceptUid: user.uid)) {
      if (created) await _users.delete(user.uid);
      throw ApiException.validation({'studentId': _studentIdTakenMessage});
    }
    try {
      await _credentials.create(user.uid, username: username, passwordHash: passwordHash);
    } on StateError catch (e) {
      if (e.message == 'credential_exists') {
        throw ApiException.conflict('Email này đã được đăng ký. Hãy đăng nhập.', code: 'email_registered');
      }
      throw ApiException.validation({'username': 'Tên đăng nhập này vừa có người dùng. Hãy đăng ký lại với tên khác.'});
    }
    try {
      user = await _users.update(
        user.uid,
        username: username,
        studentId: studentId,
        displayName: user.profileComplete ? null : name,
        // Tài khoản quản trị tạo trước giữ đối tượng đã gán (vd: Nhân viên của bảo vệ).
        memberType: created ? MemberType.tryFromWire(pending['memberType']) : null,
        role: isBootstrapAdmin && user.role != UserRole.admin ? UserRole.admin : null,
        lastLoginAt: _clock().toUtc(),
      );
    } on StateError catch (e) {
      if (e.message != 'student_id_taken') rethrow;
      // Hai người đăng ký cùng MSSV đúng cùng lúc: chỉ mục unique chặn người sau.
      await _credentials.delete(user.uid);
      if (created) await _users.delete(user.uid);
      throw ApiException.validation({'studentId': _studentIdTakenMessage});
    }
    final token = await _auth.createCustomToken(user.uid, claims: {'role': user.role.wire});
    return SignInResult(customToken: token, user: user, isNewUser: created);
  }

  // ---------------------------------------------------------------- Quên mật khẩu

  /// Gửi mã đặt lại mật khẩu tới email của một tài khoản đã đăng ký.
  Future<OtpRequestResult> requestPasswordReset(String rawEmail, {required String ip}) async {
    final email = _parseEmail(rawEmail);
    final user = await _users.byEmail(email);
    final cred = user == null ? null : await _credentials.byUid(user.uid);
    if (user == null || cred == null) {
      throw ApiException.validation({'email': 'Email này chưa đăng ký tài khoản. Hãy kiểm tra lại hoặc đăng ký.'});
    }
    if (!user.active) {
      throw ApiException.forbidden('Tài khoản này đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
    }
    _limitSends(ip);
    return _sendCode(email, action: 'đặt lại mật khẩu', pending: {'purpose': 'reset', 'uid': user.uid});
  }

  /// Nhập đúng mã thì đặt mật khẩu mới (mở khoá đăng nhập nếu đang bị khoá) và đăng nhập luôn.
  Future<SignInResult> resetPassword(String rawEmail, String rawCode, String newPassword, {required String ip}) async {
    final email = _parseEmail(rawEmail);
    final passwordError = PasswordPolicy.validate(newPassword);
    if (passwordError != null) throw ApiException.validation({'password': passwordError});
    final pending = await _checkCode(email, rawCode, ip: ip, purpose: 'reset');
    final user = await _users.byEmail(email);
    if (user == null || user.uid != pending['uid'] || await _credentials.byUid(user.uid) == null) {
      throw ApiException.badRequest('Tài khoản không còn tồn tại.', code: 'account_missing');
    }
    if (!user.active) throw ApiException.forbidden('Tài khoản này đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
    await _credentials.updatePassword(user.uid, await _hasher.hashAsync(newPassword));
    // Đăng xuất các máy đang dùng mật khẩu cũ.
    await _auth.revokeSessions(user.uid);
    final updated = await _users.update(user.uid, lastLoginAt: _clock().toUtc());
    final token = await _auth.createCustomToken(updated.uid, claims: {'role': updated.role.wire});
    return SignInResult(customToken: token, user: updated, isNewUser: false);
  }

  // ---------------------------------------------------------------- Đổi mật khẩu

  /// Người dùng đang đăng nhập đổi mật khẩu: phải nhập đúng mật khẩu hiện tại. Các máy khác bị đăng
  /// xuất (phòng trường hợp lộ mật khẩu); máy đang dùng nhận phiên mới qua custom token trả về.
  Future<SignInResult> changePassword(UserRecord user, String currentPassword, String newPassword) async {
    final cred = await _credentials.byUid(user.uid);
    if (cred == null) {
      throw ApiException.badRequest('Tài khoản chưa có mật khẩu. Hãy dùng "Quên mật khẩu".', code: 'no_password');
    }
    final error = PasswordPolicy.validate(newPassword);
    if (error != null) throw ApiException.validation({'newPassword': error});
    if (!await _hasher.verifyAsync(currentPassword, cred.passwordHash)) {
      throw ApiException.validation({'currentPassword': 'Mật khẩu hiện tại không đúng.'});
    }
    if (currentPassword == newPassword) {
      throw ApiException.validation({'newPassword': 'Mật khẩu mới phải khác mật khẩu hiện tại.'});
    }
    await _credentials.updatePassword(user.uid, await _hasher.hashAsync(newPassword));
    await _auth.revokeSessions(user.uid);
    final token = await _auth.createCustomToken(user.uid, claims: {'role': user.role.wire});
    return SignInResult(customToken: token, user: user, isNewUser: false);
  }

  // ---------------------------------------------------------------- Xoá tài khoản

  /// Quản trị xoá tài khoản: hồ sơ, tên đăng nhập, mật khẩu và tài khoản Firebase Auth.
  /// Báo cáo người đó đã gửi vẫn giữ để tra cứu. Không xoá được chính mình và quản trị gốc (.env).
  Future<void> deleteAccount(UserRecord admin, String uid) async {
    if (admin.role != UserRole.admin) throw ApiException.forbidden();
    if (uid == admin.uid) throw ApiException.forbidden('Bạn không thể tự xoá tài khoản của mình.');
    final target = await _users.byId(uid);
    if (target == null) throw ApiException.notFound('Không tìm thấy tài khoản.');
    if (_bootstrapAdmins.contains(target.email)) {
      throw ApiException.forbidden('Đây là tài khoản quản trị gốc (BOOTSTRAP_ADMIN_EMAILS), không xoá được.');
    }
    await _auth.revokeSessions(uid);
    await _credentials.delete(uid);
    await _users.delete(uid);
    await _auth.deleteUser(uid);
  }

  // ---------------------------------------------------------------- Đăng nhập

  /// [identifier] là tên đăng nhập hoặc email.
  /// Số lần đăng nhập sai liên tiếp và thời điểm hết tạm khoá của từng tài khoản (màn quản trị).
  /// Tài khoản chưa có mật khẩu (quản trị tạo trước, chưa kích hoạt) không có trong kết quả.
  Future<Map<String, Map<String, Object?>>> loginStatus(Iterable<String> uids) async {
    final now = _clock().toUtc();
    final entries = await Future.wait(uids.map((uid) async => (uid, await _credentials.byUid(uid))));
    return {
      for (final (uid, cred) in entries)
        if (cred != null)
          uid: {
            'failedLogins': (cred.lockedUntil?.isAfter(now) ?? false) ? LoginPolicy.maxFailures : cred.failedAttempts,
            'maxLoginFailures': LoginPolicy.maxFailures,
            'loginLockedUntil': (cred.lockedUntil?.isAfter(now) ?? false) ? cred.lockedUntil!.toIso8601String() : null,
          },
    };
  }

  /// Quản trị đặt số lần đăng nhập sai của [uid]: đủ [LoginPolicy.maxFailures] thì tạm khoá như
  /// khi tự nhập sai, ít hơn thì mở khoá ngay (0 là mở khoá hẳn).
  Future<void> setFailedLogins(String uid, int count) async {
    if (count < 0 || count > LoginPolicy.maxFailures) {
      throw ApiException.validation({'failedLogins': 'Số lần cảnh báo từ 0 đến ${LoginPolicy.maxFailures}.'});
    }
    if (await _credentials.byUid(uid) == null) {
      throw ApiException.validation({'failedLogins': 'Tài khoản chưa kích hoạt nên chưa có lần đăng nhập nào.'});
    }
    if (count >= LoginPolicy.maxFailures) {
      await _credentials.recordFailure(uid, attempts: 0, lockedUntil: _clock().toUtc().add(LoginPolicy.lockDuration));
    } else {
      await _credentials.recordFailure(uid, attempts: count);
    }
  }

  Future<SignInResult> login(String identifier, String password, {required String ip}) async {
    final ipWait = _ipLogin.hit(ip);
    if (ipWait != null) {
      throw ApiException.tooManyRequests(
        'Bạn thử đăng nhập quá nhiều lần. Thử lại sau ${humanizeWait(ipWait)}.',
        retryAfter: ipWait,
      );
    }
    final id = identifier.trim();
    if (id.isEmpty || password.isEmpty) {
      throw ApiException.validation({
        if (id.isEmpty) 'username': 'Nhập tên đăng nhập hoặc email.',
        if (password.isEmpty) 'password': 'Nhập mật khẩu.',
      });
    }

    StoredCredential? cred;
    if (id.contains('@')) {
      final email = EmailAddress.tryParse(id);
      final user = email == null ? null : await _users.byEmail(email);
      cred = user == null ? null : await _credentials.byUid(user.uid);
    } else {
      cred = await _credentials.byUsername(UsernamePolicy.normalize(id));
    }
    if (cred == null) {
      // Vẫn băm để thời gian phản hồi không lộ tên đăng nhập có tồn tại hay không.
      await _hasher.verifyAsync(password, await _dummyHash);
      throw ApiException(HttpStatus.unauthorized, 'invalid_credentials', _invalidLogin);
    }

    final now = _clock().toUtc();
    final locked = cred.lockedUntil;
    if (locked != null && locked.isAfter(now)) {
      throw ApiException.tooManyRequests(
        'Tài khoản tạm khoá do nhập sai mật khẩu nhiều lần. Thử lại sau ${humanizeWait(locked.difference(now))}.',
        retryAfter: locked.difference(now),
        code: 'login_locked',
      );
    }

    if (!await _hasher.verifyAsync(password, cred.passwordHash)) {
      final attempts = (locked != null ? 0 : cred.failedAttempts) + 1;
      if (attempts >= LoginPolicy.maxFailures) {
        await _credentials.recordFailure(cred.uid, attempts: 0, lockedUntil: now.add(LoginPolicy.lockDuration));
        throw ApiException.tooManyRequests(
          'Sai mật khẩu ${LoginPolicy.maxFailures} lần. Tài khoản tạm khoá ${LoginPolicy.lockDuration.inMinutes} phút.',
          retryAfter: LoginPolicy.lockDuration,
          code: 'login_locked',
        );
      }
      await _credentials.recordFailure(cred.uid, attempts: attempts);
      // Nhóm chọn báo số lần sai để người dùng biết sắp bị khoá, chấp nhận việc tên đăng nhập có
      // thật thì phản hồi khác tên không tồn tại.
      throw ApiException(
        HttpStatus.unauthorized,
        'invalid_credentials',
        'Sai mật khẩu $attempts/${LoginPolicy.maxFailures} lần. '
            'Sai ${LoginPolicy.maxFailures} lần sẽ tạm khoá đăng nhập ${LoginPolicy.lockDuration.inMinutes} phút.',
        details: {'failedAttempts': attempts, 'maxFailures': LoginPolicy.maxFailures},
      );
    }

    final user = await _users.byId(cred.uid);
    if (user == null) throw ApiException(HttpStatus.unauthorized, 'invalid_credentials', _invalidLogin);
    if (!user.active) throw ApiException.forbidden('Tài khoản này đã bị khoá. Liên hệ quản trị để được hỗ trợ.');
    if (cred.failedAttempts > 0 || locked != null) await _credentials.resetFailures(cred.uid);

    final isBootstrapAdmin = _bootstrapAdmins.contains(user.email);
    final updated = await _users.update(
      user.uid,
      role: isBootstrapAdmin && user.role != UserRole.admin ? UserRole.admin : null,
      lastLoginAt: now,
    );
    final token = await _auth.createCustomToken(updated.uid, claims: {'role': updated.role.wire});
    return SignInResult(customToken: token, user: updated, isNewUser: false);
  }

  late final Future<String> _dummyHash = _hasher.hashAsync('khong-phai-mat-khau-1');

  // ---------------------------------------------------------------- OTP

  void _limitSends(String ip) {
    final ipWait = _ipSend.hit(ip);
    if (ipWait != null) {
      throw ApiException.tooManyRequests(
        'Có quá nhiều yêu cầu mã từ mạng của bạn. Thử lại sau ${humanizeWait(ipWait)}.',
        retryAfter: ipWait,
      );
    }
  }

  Future<OtpRequestResult> _sendCode(
    EmailAddress email, {
    required String action,
    required Map<String, String> pending,
  }) async {
    final now = _clock().toUtc();
    final code = _random.nextInt(1000000).toString().padLeft(OtpPolicy.codeLength, '0');
    final salt = _randomHex(16);
    final key = challengeKey(email);

    await _store.update(key, (current) {
      final recent = (current?.sendTimes ?? const <DateTime>[])
          .where((t) => now.difference(t) < const Duration(hours: 24))
          .toList()
        ..sort();
      if (recent.isNotEmpty) {
        final sinceLast = now.difference(recent.last);
        if (sinceLast < OtpPolicy.resendCooldown) {
          final wait = OtpPolicy.resendCooldown - sinceLast;
          throw ApiException.tooManyRequests(
            'Vui lòng đợi ${humanizeWait(wait)} trước khi gửi lại mã.',
            retryAfter: wait,
            code: 'otp_cooldown',
          );
        }
      }
      // Xét giới hạn ngày trước để báo đúng thời gian phải chờ (dài hơn).
      if (recent.length >= OtpPolicy.maxSendsPerDay) {
        final wait = const Duration(hours: 24) - now.difference(recent.first);
        throw ApiException.tooManyRequests(
          'Email này đã yêu cầu ${OtpPolicy.maxSendsPerDay} mã trong 24 giờ. Thử lại sau ${humanizeWait(wait)}.',
          retryAfter: wait,
          code: 'otp_daily_limit',
        );
      }
      final lastHour = recent.where((t) => now.difference(t) < const Duration(hours: 1)).toList();
      if (lastHour.length >= OtpPolicy.maxSendsPerHour) {
        final wait = const Duration(hours: 1) - now.difference(lastHour.first);
        throw ApiException.tooManyRequests(
          'Bạn đã yêu cầu ${OtpPolicy.maxSendsPerHour} mã trong 1 giờ. Thử lại sau ${humanizeWait(wait)}.',
          retryAfter: wait,
          code: 'otp_hourly_limit',
        );
      }
      return OtpChallenge(
        codeHash: hashCode6(email, code, salt),
        salt: salt,
        expiresAt: now.add(OtpPolicy.ttl),
        attempts: 0,
        sendTimes: [...recent, now],
        pending: pending,
      );
    });

    try {
      await _mailer.sendOtp(email, code, ttl: OtpPolicy.ttl, action: action);
    } on OtpMailException catch (e) {
      // Lần gửi vẫn được tính vào giới hạn (chống spam), nhưng mã không còn dùng được.
      await _store.update(key, (c) => (c ?? const OtpChallenge()).copyWith(clearCode: true));
      throw ApiException(HttpStatus.serviceUnavailable, 'email_send_failed', e.message);
    }
    return OtpRequestResult(
      email: email,
      expiresIn: OtpPolicy.ttl,
      resendAfter: OtpPolicy.resendCooldown,
      mode: _mailer.mode,
    );
  }

  /// Kiểm tra mã; đúng thì xoá mã (dùng một lần) và trả về thông tin đăng ký đang chờ.
  Future<Map<String, String>> _checkCode(
    EmailAddress email,
    String rawCode, {
    required String ip,
    required String purpose,
  }) async {
    final ipWait = _ipVerify.hit(ip);
    if (ipWait != null) {
      throw ApiException.tooManyRequests(
        'Bạn thử quá nhiều lần. Thử lại sau ${humanizeWait(ipWait)}.',
        retryAfter: ipWait,
      );
    }
    final codeError = OtpPolicy.validateCode(rawCode);
    if (codeError != null) throw ApiException.badRequest(codeError, code: 'otp_format');
    final code = rawCode.trim();
    final now = _clock().toUtc();

    Map<String, String>? pending;
    final updated = await _store.update(challengeKey(email), (c) {
      pending = null;
      // Phiên cũ (trước khi có mục đích) được coi là mã đăng ký.
      if (c == null || !c.hasActiveCode || (c.pending['purpose'] ?? 'register') != purpose) {
        throw ApiException.badRequest(
          'Mã OTP không đúng hoặc đã được dùng. Hãy yêu cầu mã mới.',
          code: 'otp_invalid',
        );
      }
      if (c.attempts >= OtpPolicy.maxVerifyAttempts) {
        throw ApiException.tooManyRequests(
          'Bạn đã nhập sai ${OtpPolicy.maxVerifyAttempts} lần. Hãy yêu cầu mã mới.',
          code: 'otp_locked',
        );
      }
      if (now.isAfter(c.expiresAt!)) {
        throw ApiException.badRequest('Mã OTP đã hết hạn. Hãy yêu cầu mã mới.', code: 'otp_expired');
      }
      if (_constantTimeEquals(hashCode6(email, code, c.salt!), c.codeHash!)) {
        pending = c.pending;
        return c.copyWith(clearCode: true, attempts: 0);
      }
      return c.copyWith(attempts: c.attempts + 1);
    });

    final result = pending;
    if (result == null) {
      final left = OtpPolicy.maxVerifyAttempts - updated.attempts;
      if (left <= 0) {
        throw ApiException.tooManyRequests(
          'Bạn đã nhập sai ${OtpPolicy.maxVerifyAttempts} lần. Hãy yêu cầu mã mới.',
          code: 'otp_locked',
        );
      }
      throw ApiException.badRequest('Mã OTP không đúng. Bạn còn $left lần thử.', code: 'otp_wrong');
    }
    return result;
  }

  EmailAddress _parseEmail(String raw) {
    try {
      return EmailAddress.parse(raw);
    } on EmailFormatException catch (e) {
      throw ApiException.validation({'email': e.message});
    }
  }

  String _randomHex(int bytes) =>
      List.generate(bytes, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

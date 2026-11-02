// Bản cài đặt trong bộ nhớ CHỈ dùng cho unit test, để chạy nhanh mà không cần Firebase.
// Mã chạy thật luôn dùng MongoDB và gửi mail thật (xem lib/src/app_services.dart).
import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:campus_safety_backend/src/notifications/push_service.dart';

class MemoryOtpStore implements OtpStore {
  final data = <String, OtpChallenge>{};

  @override
  Future<OtpChallenge?> read(String key) async => data[key];

  @override
  Future<OtpChallenge> update(String key, OtpChallenge Function(OtpChallenge? current) mutate) async {
    final next = mutate(data[key]);
    data[key] = next;
    return next;
  }
}

class MemoryUserRepository implements UserRepository {
  final byUid = <String, UserRecord>{};
  var _seq = 0;

  /// [email] mặc định `u<số>@test.vn`; [phone] tuỳ chọn.
  UserRecord seed({
    String? email,
    String? phone,
    String name = '',
    UserRole role = UserRole.reporter,
    bool active = true,
    bool onDuty = false,
    List<String> tokens = const [],
  }) {
    final uid = 'u${++_seq}';
    final u = UserRecord(
      uid: uid,
      email: EmailAddress.parse(email ?? '$uid@test.vn'),
      phone: phone == null ? null : VietnamPhone.parse(phone),
      displayName: name,
      role: role,
      memberType: MemberType.other,
      active: active,
      onDuty: onDuty,
      fcmTokens: tokens,
    );
    byUid[u.uid] = u;
    return u;
  }

  @override
  Future<UserRecord?> byId(String uid) async => byUid[uid];

  @override
  Future<UserRecord?> byEmail(EmailAddress email) async =>
      byUid.values.where((u) => u.email == email).firstOrNull;

  @override
  Future<UserRecord?> byStudentId(String studentId) async =>
      byUid.values.where((u) => u.studentId == studentId).firstOrNull;

  @override
  Future<(UserRecord, bool)> getOrCreate(EmailAddress email, {required UserRole role}) async {
    final existing = await byEmail(email);
    if (existing != null) return (existing, false);
    return (seed(email: email.value, role: role), true);
  }

  @override
  Future<UserRecord> create({
    required EmailAddress email,
    required String displayName,
    required UserRole role,
    required MemberType memberType,
    VietnamPhone? phone,
    bool onDuty = false,
  }) async {
    if (await byEmail(email) != null) throw StateError('email_exists');
    return seed(email: email.value, phone: phone?.local, name: displayName, role: role, onDuty: onDuty);
  }

  @override
  Future<UserRecord> update(
    String uid, {
    String? displayName,
    VietnamPhone? phone,
    bool clearPhone = false,
    String? username,
    String? studentId,
    int? fakeReports,
    MemberType? memberType,
    UserRole? role,
    bool? active,
    bool? onDuty,
    DateTime? lastLoginAt,
  }) async {
    if (studentId != null && byUid.values.any((u) => u.uid != uid && u.studentId == studentId)) {
      throw StateError('student_id_taken');
    }
    final u = byUid[uid]!.copyWith(
      displayName: displayName,
      phone: phone,
      clearPhone: clearPhone,
      username: username,
      studentId: studentId,
      fakeReports: fakeReports,
      memberType: memberType,
      role: role,
      active: active,
      onDuty: onDuty,
      lastLoginAt: lastLoginAt,
    );
    return byUid[uid] = u;
  }

  @override
  Future<UserRecord?> addFakeReports(String uid, int delta) async {
    final u = byUid[uid];
    if (u == null) return null;
    return byUid[uid] = u.copyWith(fakeReports: u.fakeReports + delta);
  }

  @override
  Future<void> addFcmToken(String uid, String token) async {
    final u = byUid[uid]!;
    byUid[uid] = u.copyWith(fcmTokens: {...u.fcmTokens, token}.toList());
  }

  @override
  Future<void> removeFcmToken(String uid, String token) async {
    final u = byUid[uid]!;
    byUid[uid] = u.copyWith(fcmTokens: u.fcmTokens.where((t) => t != token).toList());
  }

  @override
  Future<void> delete(String uid) async => byUid.remove(uid);

  @override
  Future<List<UserRecord>> listActive() async => byUid.values.where((u) => u.active).toList();

  @override
  Future<List<UserRecord>> listStaff() async =>
      byUid.values.where((u) => u.role.isStaff && u.active).toList();

  @override
  Future<List<UserRecord>> listByRoles(Set<UserRole> roles) async =>
      byUid.values.where((u) => roles.contains(u.role)).toList();
}

class MemoryCredentialRepository implements CredentialRepository {
  final byUidMap = <String, StoredCredential>{};

  @override
  Future<StoredCredential?> byUid(String uid) async => byUidMap[uid];

  @override
  Future<StoredCredential?> byUsername(String username) async =>
      byUidMap.values.where((c) => c.username == username).firstOrNull;

  @override
  Future<bool> usernameTaken(String username) async => byUidMap.values.any((c) => c.username == username);

  @override
  Future<void> create(String uid, {required String username, required String passwordHash}) async {
    if (await usernameTaken(username)) throw StateError('username_taken');
    if (byUidMap.containsKey(uid)) throw StateError('credential_exists');
    byUidMap[uid] = StoredCredential(uid: uid, username: username, passwordHash: passwordHash);
  }

  @override
  Future<void> recordFailure(String uid, {required int attempts, DateTime? lockedUntil}) async {
    final c = byUidMap[uid]!;
    byUidMap[uid] = StoredCredential(
      uid: uid,
      username: c.username,
      passwordHash: c.passwordHash,
      failedAttempts: attempts,
      lockedUntil: lockedUntil,
    );
  }

  @override
  Future<void> resetFailures(String uid) async {
    final c = byUidMap[uid]!;
    byUidMap[uid] = StoredCredential(uid: uid, username: c.username, passwordHash: c.passwordHash);
  }

  @override
  Future<void> updatePassword(String uid, String passwordHash) async {
    final c = byUidMap[uid]!;
    byUidMap[uid] = StoredCredential(uid: uid, username: c.username, passwordHash: passwordHash);
  }

  @override
  Future<void> delete(String uid) async => byUidMap.remove(uid);
}

class MemoryReportRepository implements ReportRepository {
  final reports = <String, ReportRecord>{};
  final privates = <String, ReporterPrivate>{};
  final events = <String, List<ReportEvent>>{};
  final userIndex = <String, Set<String>>{};
  var _seq = 0;

  @override
  String newId() => 'r${++_seq}';

  @override
  Future<void> create(ReportRecord report, ReporterPrivate reporter, ReportEvent createdEvent) async {
    reports[report.id] = report;
    privates[report.id] = reporter;
    events[report.id] = [createdEvent];
    userIndex.putIfAbsent(reporter.uid, () => {}).add(report.id);
  }

  @override
  Future<ReportRecord?> byId(String id) async => reports[id];

  @override
  Future<ReporterPrivate?> reporterOf(String id) async => privates[id];

  @override
  Future<(ReportRecord, ReporterPrivate)> mutate(
    String id,
    (ReportRecord, ReportEvent?) Function(ReportRecord current, ReporterPrivate reporter) apply,
  ) async {
    final current = reports[id];
    final reporter = privates[id];
    if (current == null || reporter == null) throw StateError('report_not_found');
    final (next, event) = apply(current, reporter);
    reports[id] = next;
    if (event != null) events[id]!.add(event);
    return (next, reporter);
  }

  @override
  Future<void> addEvent(String reportId, ReportEvent event) async => events[reportId]!.add(event);

  @override
  Future<List<ReportEvent>> eventsOf(String id) async => events[id] ?? const [];

  List<ReportRecord> _newest(bool Function(ReportRecord) test, int limit) =>
      (reports.values.where(test).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList();

  @override
  Future<List<ReportRecord>> listOpen({required int limit}) async => _newest((r) => !r.status.isClosed, limit);

  @override
  Future<List<ReportRecord>> listSince(DateTime from, {required int limit}) async =>
      _newest((r) => !r.createdAt.isBefore(from), limit);

  @override
  Future<List<ReportRecord>> listAssignedTo(String uid, {required int limit}) async =>
      _newest((r) => r.assigneeUid == uid, limit);

  @override
  Future<List<ReportRecord>> listByReporter(String uid, {required int limit}) async =>
      _newest((r) => privates[r.id]?.uid == uid, limit);
}

/// Ghi lại email OTP cần gửi; [failWith] khác null thì giả lập gửi thất bại.
class RecordingOtpMailer implements OtpMailer {
  final sent = <(EmailAddress, String)>[];
  OtpMailException? failWith;

  final actions = <String>[];

  @override
  String get mode => 'email';

  @override
  Future<void> sendOtp(EmailAddress to, String code, {required Duration ttl, String action = 'đăng ký tài khoản'}) async {
    final error = failWith;
    if (error != null) throw error;
    sent.add((to, code));
    actions.add(action);
  }
}

class RecordingPushService implements PushService {
  final sent = <(List<String>, PushMessage)>[];
  final invalid = <String>{};

  @override
  Future<PushResult> sendToTokens(List<String> tokens, PushMessage message) async {
    sent.add((tokens, message));
    return PushResult(
      successCount: tokens.where((t) => !invalid.contains(t)).length,
      failureCount: tokens.where(invalid.contains).length,
      invalidTokens: tokens.where(invalid.contains).toList(),
    );
  }
}

class FakeAuthTokens implements AuthTokenService {
  final issued = <String, Map<String, Object?>?>{};
  final revoked = <String>[];

  @override
  Future<String> createCustomToken(String uid, {Map<String, Object?>? claims}) async {
    issued[uid] = claims;
    return 'custom-token-$uid';
  }

  @override
  Future<String> verifyIdToken(String idToken) async {
    if (!idToken.startsWith('id-')) throw InvalidIdTokenException('bad');
    return idToken.substring(3);
  }

  @override
  Future<void> revokeSessions(String uid) async => revoked.add(uid);

  final deleted = <String>[];

  @override
  Future<void> deleteUser(String uid) async => deleted.add(uid);
}

/// Đồng hồ điều khiển được.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

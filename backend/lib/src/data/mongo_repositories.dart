import 'dart:math';

import 'package:campus_core/campus_core.dart';
import 'package:mongo_dart/mongo_dart.dart' show ModifierBuilder, ObjectId, modify, where;

import 'models.dart';
import 'mongo_store.dart';
import 'repositories.dart';

DateTime? readDate(Object? v) => switch (v) {
      final DateTime d => d.toUtc(),
      final String s => DateTime.tryParse(s)?.toUtc(),
      _ => null,
    };

double? readDouble(Object? v) => v is num ? v.toDouble() : null;

String? readString(Object? v) => v is String && v.isNotEmpty ? v : null;

List<String> readStringList(Object? v) => v is List ? v.whereType<String>().toList() : const [];

/// Sinh ID chuỗi cho tài liệu mới.
String newDocumentId() => ObjectId().oid;

/// `$set` mọi trường của [doc].
ModifierBuilder setAll(Map<String, Object?> doc) {
  final builder = modify;
  doc.forEach(builder.set);
  return builder;
}

/// Số lần thử lại khi có người khác ghi cùng lúc (khoá lạc quan theo trường `v`).
const maxWriteAttempts = 20;

/// Chờ ngẫu nhiên trước lần thử lại để các bên đang ghi không va nhau mãi.
Future<void> backoff(int attempt) =>
    attempt == 0 ? Future.value() : Future.delayed(Duration(milliseconds: _random.nextInt(40 * attempt)));

final _random = Random();

class MongoUserRepository implements UserRepository {
  MongoUserRepository(this._store, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final MongoStore _store;
  final DateTime Function() _clock;

  static const _name = Collections.users;

  static UserRecord? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final email = EmailAddress.tryParse(d['email'] as String?);
    if (email == null) return null;
    return UserRecord(
      uid: d['_id'] as String,
      email: email,
      phone: VietnamPhone.tryParse(d['phone'] as String?),
      username: readString(d['username']),
      studentId: readString(d['studentId']),
      fakeReports: (d['fakeReports'] as num?)?.toInt() ?? 0,
      displayName: (d['displayName'] as String?) ?? '',
      role: UserRole.fromWire(d['role'] as String?),
      memberType: MemberType.fromWire(d['memberType'] as String?),
      active: d['active'] != false,
      onDuty: d['onDuty'] == true,
      fcmTokens: readStringList(d['fcmTokens']),
      createdAt: readDate(d['createdAt']),
      updatedAt: readDate(d['updatedAt']),
      lastLoginAt: readDate(d['lastLoginAt']),
    );
  }

  static Map<String, Object?> toDoc(UserRecord u) => {
        '_id': u.uid,
        'email': u.email.value,
        'username': u.username,
        // Chỉ mục unique của MSSV bỏ qua tài liệu không có trường này, nên không ghi null.
        'studentId': ?u.studentId,
        'fakeReports': u.fakeReports,
        'phone': u.phone?.international,
        'phoneLocal': u.phone?.local,
        'displayName': u.displayName,
        'role': u.role.wire,
        'memberType': u.memberType.wire,
        'active': u.active,
        'onDuty': u.onDuty,
        'fcmTokens': u.fcmTokens,
        'createdAt': u.createdAt,
        'updatedAt': u.updatedAt,
        'lastLoginAt': u.lastLoginAt,
      };

  @override
  Future<UserRecord?> byId(String uid) async =>
      fromDoc(await _store.run(_name, (c) => c.findOne(where.eq('_id', uid))));

  @override
  Future<UserRecord?> byEmail(EmailAddress email) async =>
      fromDoc(await _store.run(_name, (c) => c.findOne(where.eq('email', email.value))));

  @override
  Future<UserRecord?> byStudentId(String studentId) async =>
      fromDoc(await _store.run(_name, (c) => c.findOne(where.eq('studentId', studentId))));

  /// Chèn [user]; chỉ mục unique trên `email` đảm bảo mỗi email một tài khoản. `false` nếu đã có.
  Future<bool> _insert(UserRecord user) async {
    final doc = Map<String, dynamic>.of(toDoc(user));
    final result = await _store.run(_name, (c) => c.insertOne(doc));
    if (MongoStore.isDuplicate(result)) return false;
    if (!result.isSuccess) throw StateError('insert_user_failed');
    return true;
  }

  @override
  Future<(UserRecord, bool)> getOrCreate(EmailAddress email, {required UserRole role}) async {
    final existing = await byEmail(email);
    if (existing != null) return (existing, false);
    final now = _clock().toUtc();
    final user = UserRecord(
      uid: newDocumentId(),
      email: email,
      displayName: '',
      role: role,
      memberType: MemberType.other,
      active: true,
      onDuty: false,
      createdAt: now,
      updatedAt: now,
    );
    if (await _insert(user)) return (user, true);
    final raced = await byEmail(email);
    if (raced == null) throw StateError('user_not_found');
    return (raced, false);
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
    final now = _clock().toUtc();
    final user = UserRecord(
      uid: newDocumentId(),
      email: email,
      phone: phone,
      displayName: displayName,
      role: role,
      memberType: memberType,
      active: true,
      onDuty: onDuty && role.isStaff,
      createdAt: now,
      updatedAt: now,
    );
    if (!await _insert(user)) throw StateError('email_exists');
    return user;
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
    final result = await _store.run(
      _name,
      (c) => c.updateOne(
        where.eq('_id', uid),
        setAll({
          'displayName': ?displayName,
          if (clearPhone) ...{'phone': null, 'phoneLocal': null},
          if (phone != null) ...{'phone': phone.international, 'phoneLocal': phone.local},
          'username': ?username,
          'studentId': ?studentId,
          'fakeReports': ?fakeReports,
          if (memberType != null) 'memberType': memberType.wire,
          if (role != null) 'role': role.wire,
          'active': ?active,
          'onDuty': ?onDuty,
          if (lastLoginAt != null) 'lastLoginAt': lastLoginAt.toUtc(),
          'updatedAt': _clock().toUtc(),
        }),
      ),
    );
    if (MongoStore.isDuplicate(result)) throw StateError('student_id_taken');
    final updated = await byId(uid);
    if (updated == null) throw StateError('user_not_found');
    return updated;
  }

  @override
  Future<UserRecord?> addFakeReports(String uid, int delta) async {
    final result = await _store.run(
      _name,
      (c) => c.modernFindAndModify(
        query: where.eq('_id', uid),
        update: modify
          ..inc('fakeReports', delta)
          ..set('updatedAt', _clock().toUtc()),
        returnNew: true,
      ),
    );
    return fromDoc(result.value);
  }

  /// Giữ tối đa [maxFcmTokens] thiết bị gần nhất để danh sách không phình vô hạn.
  static const maxFcmTokens = 10;

  @override
  Future<void> addFcmToken(String uid, String token) async {
    // Máy này có thể chưa kịp huỷ token của người dùng trước (phiên hết hạn, mất mạng khi đăng xuất):
    // gỡ khỏi mọi tài khoản để sinh viên đăng nhập máy cũ của bảo vệ không nhận cảnh báo sự cố.
    await _store.run(_name, (c) => c.updateMany(where.eq('fcmTokens', token), modify.pull('fcmTokens', token)));
    await _store.run(
      _name,
      (c) => c.updateOne(where.eq('_id', uid), {
        r'$push': {
          'fcmTokens': {
            r'$each': [token],
            r'$slice': -maxFcmTokens,
          },
        },
        r'$set': {'updatedAt': _clock().toUtc()},
      }),
    );
  }

  @override
  Future<void> removeFcmToken(String uid, String token) async {
    await _store.run(_name, (c) => c.updateOne(where.eq('_id', uid), modify.pull('fcmTokens', token)));
  }

  @override
  Future<void> delete(String uid) async {
    await _store.run(_name, (c) => c.deleteOne(where.eq('_id', uid)));
  }

  Future<List<UserRecord>> _list(Object selector) async {
    final docs = await _store.run(_name, (c) => c.find(selector).toList());
    return docs.map(fromDoc).whereType<UserRecord>().toList();
  }

  @override
  Future<List<UserRecord>> listActive() => _list(where.eq('active', true));

  @override
  Future<List<UserRecord>> listStaff() async => (await listByRoles({UserRole.guard, UserRole.admin})).where((u) => u.active).toList();

  @override
  Future<List<UserRecord>> listByRoles(Set<UserRole> roles) =>
      _list(where.oneFrom('role', roles.map((r) => r.wire).toList()).limit(1000));
}

/// Mỗi báo cáo là một tài liệu, chứa luôn người báo thật (`reporter`) và lịch sử (`events`).
///
/// MongoDB ghi một tài liệu là nguyên tử, nên tạo báo cáo hay đổi trạng thái kèm một dòng lịch sử
/// không cần transaction. Trường `reporter` không bao giờ trả thẳng cho client: báo cáo ẩn danh vẫn
/// ẩn tên vì API chỉ đưa người báo cho quản trị và chính người báo (xem `ReportService.detail`).
class MongoReportRepository implements ReportRepository {
  MongoReportRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.reports;

  static Map<String, Object?> toDoc(ReportRecord r) => {
        'code': r.code,
        'type': r.type.wire,
        'severity': r.severity.wire,
        'severityRank': r.severity.rank,
        'status': r.status.wire,
        'description': r.description,
        'occurredAt': r.occurredAt.toUtc(),
        'createdAt': r.createdAt.toUtc(),
        'updatedAt': r.updatedAt.toUtc(),
        'emergency': r.emergency,
        'anonymous': r.anonymous,
        'building': r.building,
        'floor': r.floor,
        'room': r.room,
        'locationText': r.locationText,
        'latitude': r.latitude,
        'longitude': r.longitude,
        'accuracyMeters': r.accuracyMeters,
        'reporterUid': r.anonymous ? null : r.reporterUid,
        'reporterName': r.anonymous ? null : r.reporterName,
        'reporterPhone': r.anonymous ? null : r.reporterPhone,
        'reporterMemberType': r.anonymous ? null : r.reporterMemberType?.wire,
        'imagePaths': r.imagePaths,
        'assigneeUid': r.assigneeUid,
        'assigneeName': r.assigneeName,
        'lastNote': r.lastNote,
        'closedAt': r.closedAt?.toUtc(),
        'fake': r.fake,
      };

  static Map<String, Object?> eventDoc(ReportEvent e) => {
        'type': e.type.wire,
        'createdAt': e.createdAt.toUtc(),
        'actorUid': e.actorUid,
        'actorName': e.actorName,
        'actorRole': e.actorRole.wire,
        'fromStatus': e.fromStatus?.wire,
        'toStatus': e.toStatus?.wire,
        'note': e.note,
      };

  static ReportEvent? eventFromDoc(Object? v) {
    if (v is! Map) return null;
    final createdAt = readDate(v['createdAt']);
    if (createdAt == null) return null;
    return ReportEvent(
      type: ReportEventType.fromWire(v['type'] as String?),
      createdAt: createdAt,
      actorUid: readString(v['actorUid']),
      actorName: (v['actorName'] as String?) ?? '',
      actorRole: UserRole.fromWire(v['actorRole'] as String?),
      fromStatus: ReportStatus.tryFromWire(v['fromStatus'] as String?),
      toStatus: ReportStatus.tryFromWire(v['toStatus'] as String?),
      note: readString(v['note']),
    );
  }

  static ReportRecord? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final now = DateTime.now().toUtc();
    final id = d['_id'] as String;
    return ReportRecord(
      id: id,
      code: (d['code'] as String?) ?? id,
      type: IncidentType.fromWire(d['type'] as String?),
      severity: Severity.fromWire(d['severity'] as String?),
      status: ReportStatus.fromWire(d['status'] as String?),
      description: (d['description'] as String?) ?? '',
      occurredAt: readDate(d['occurredAt']) ?? now,
      createdAt: readDate(d['createdAt']) ?? now,
      updatedAt: readDate(d['updatedAt']) ?? now,
      emergency: d['emergency'] == true,
      anonymous: d['anonymous'] == true,
      building: readString(d['building']),
      floor: readString(d['floor']),
      room: readString(d['room']),
      latitude: readDouble(d['latitude']),
      longitude: readDouble(d['longitude']),
      accuracyMeters: readDouble(d['accuracyMeters']),
      reporterUid: readString(d['reporterUid']),
      reporterName: readString(d['reporterName']),
      reporterPhone: readString(d['reporterPhone']),
      reporterMemberType: MemberType.tryFromWire(d['reporterMemberType'] as String?),
      imagePaths: readStringList(d['imagePaths']),
      assigneeUid: readString(d['assigneeUid']),
      assigneeName: readString(d['assigneeName']),
      lastNote: readString(d['lastNote']),
      closedAt: readDate(d['closedAt']),
      fake: d['fake'] == true,
    );
  }

  static ReporterPrivate? reporterFromDoc(Map<String, dynamic>? doc) {
    final d = doc?['reporter'];
    if (d is! Map) return null;
    final uid = d['uid'];
    if (uid is! String) return null;
    return ReporterPrivate(
      uid: uid,
      email: EmailAddress.tryParse(d['email'] as String?),
      phone: VietnamPhone.tryParse(d['phone'] as String?),
      displayName: (d['displayName'] as String?) ?? '',
    );
  }

  static Map<String, Object?> reporterDoc(ReporterPrivate p) => {
        'uid': p.uid,
        'email': p.email?.value,
        'phone': p.phone?.international,
        'phoneLocal': p.phone?.local,
        'displayName': p.displayName,
      };

  Future<Map<String, dynamic>?> _doc(String id) => _store.run(_name, (c) => c.findOne(where.eq('_id', id)));

  @override
  String newId() => newDocumentId();

  @override
  Future<void> create(ReportRecord report, ReporterPrivate reporter, ReportEvent createdEvent) async {
    final result = await _store.run(
      _name,
      (c) => c.insertOne({
        '_id': report.id,
        ...toDoc(report),
        'reporter': reporterDoc(reporter),
        'events': [eventDoc(createdEvent)],
        'v': 0,
      }),
    );
    if (!result.isSuccess) throw StateError('insert_report_failed');
  }

  @override
  Future<ReportRecord?> byId(String id) async => fromDoc(await _doc(id));

  @override
  Future<ReporterPrivate?> reporterOf(String id) async => reporterFromDoc(await _doc(id));

  @override
  Future<List<ReportEvent>> eventsOf(String id) async {
    final events = (await _doc(id))?['events'];
    return events is List ? events.map(eventFromDoc).whereType<ReportEvent>().toList() : const [];
  }

  @override
  Future<(ReportRecord, ReporterPrivate)> mutate(
    String id,
    (ReportRecord, ReportEvent?) Function(ReportRecord current, ReporterPrivate reporter) apply,
  ) async {
    for (var attempt = 0; attempt < maxWriteAttempts; attempt++) {
      await backoff(attempt);
      final doc = await _doc(id);
      final current = fromDoc(doc);
      final reporter = reporterFromDoc(doc);
      if (current == null || reporter == null) throw StateError('report_not_found');
      final (next, event) = apply(current, reporter);
      final update = setAll(toDoc(next))..inc('v', 1);
      if (event != null) update.push('events', eventDoc(event));
      final result = await _store.run(
        _name,
        (c) => c.modernFindAndModify(query: where.eq('_id', id).eq('v', (doc!['v'] as int?) ?? 0), update: update, returnNew: true),
      );
      if (result.value != null) return (next, reporter);
    }
    throw StateError('report_write_conflict');
  }

  @override
  Future<void> addEvent(String reportId, ReportEvent event) async {
    await _store.run(
      _name,
      (c) => c.updateOne(
        where.eq('_id', reportId),
        modify
          ..push('events', eventDoc(event))
          ..set('updatedAt', event.createdAt.toUtc())
          ..inc('v', 1),
      ),
    );
  }

  Future<List<ReportRecord>> _list(Object selector) async {
    final docs = await _store.run(_name, (c) => c.find(selector).toList());
    return docs.map(fromDoc).whereType<ReportRecord>().toList();
  }

  @override
  Future<List<ReportRecord>> listOpen({required int limit}) => _list(
        where
            .oneFrom('status', [ReportStatus.submitted.wire, ReportStatus.received.wire, ReportStatus.inProgress.wire])
            .sortBy('createdAt', descending: true)
            .limit(limit),
      );

  @override
  Future<List<ReportRecord>> listSince(DateTime from, {required int limit}) =>
      _list(where.gte('createdAt', from.toUtc()).sortBy('createdAt', descending: true).limit(limit));

  @override
  Future<List<ReportRecord>> listAssignedTo(String uid, {required int limit}) =>
      _list(where.eq('assigneeUid', uid).sortBy('createdAt', descending: true).limit(limit));

  @override
  Future<List<ReportRecord>> listByReporter(String uid, {required int limit}) =>
      _list(where.eq('reporter.uid', uid).sortBy('createdAt', descending: true).limit(limit));
}

class MongoCredentialRepository implements CredentialRepository {
  MongoCredentialRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.credentials;

  static StoredCredential? _from(Map<String, dynamic>? d) {
    if (d == null) return null;
    final username = readString(d['username']);
    final hash = readString(d['passwordHash']);
    if (username == null || hash == null) return null;
    return StoredCredential(
      uid: d['_id'] as String,
      username: username,
      passwordHash: hash,
      failedAttempts: (d['failedAttempts'] as num?)?.toInt() ?? 0,
      lockedUntil: readDate(d['lockedUntil']),
    );
  }

  @override
  Future<StoredCredential?> byUid(String uid) async => _from(await _store.run(_name, (c) => c.findOne(where.eq('_id', uid))));

  @override
  Future<StoredCredential?> byUsername(String username) async =>
      _from(await _store.run(_name, (c) => c.findOne(where.eq('username', username))));

  @override
  Future<bool> usernameTaken(String username) async => await byUsername(username) != null;

  @override
  Future<void> create(String uid, {required String username, required String passwordHash}) async {
    final result = await _store.run(
      _name,
      (c) => c.insertOne({
        '_id': uid,
        'username': username,
        'passwordHash': passwordHash,
        'failedAttempts': 0,
        'lockedUntil': null,
        'createdAt': DateTime.now().toUtc(),
      }),
    );
    if (MongoStore.isDuplicate(result)) {
      final onUsername = result.writeError?.errmsg?.contains('username') ?? false;
      throw StateError(onUsername ? 'username_taken' : 'credential_exists');
    }
    if (!result.isSuccess) throw StateError('insert_credential_failed');
  }

  Future<void> _set(String uid, Map<String, Object?> fields) async {
    await _store.run(_name, (c) => c.updateOne(where.eq('_id', uid), setAll(fields)));
  }

  @override
  Future<void> recordFailure(String uid, {required int attempts, DateTime? lockedUntil}) =>
      _set(uid, {'failedAttempts': attempts, 'lockedUntil': lockedUntil?.toUtc()});

  @override
  Future<void> resetFailures(String uid) => _set(uid, {'failedAttempts': 0, 'lockedUntil': null});

  @override
  Future<void> updatePassword(String uid, String passwordHash) => _set(uid, {
        'passwordHash': passwordHash,
        'failedAttempts': 0,
        'lockedUntil': null,
        'passwordChangedAt': DateTime.now().toUtc(),
      });

  @override
  Future<void> delete(String uid) async {
    await _store.run(_name, (c) => c.deleteOne(where.eq('_id', uid)));
  }
}

class MongoOtpStore implements OtpStore {
  MongoOtpStore(this._store);

  final MongoStore _store;

  static const _name = Collections.otp;

  static OtpChallenge? fromData(Map<String, dynamic>? d) {
    if (d == null) return null;
    return OtpChallenge(
      codeHash: readString(d['codeHash']),
      salt: readString(d['salt']),
      expiresAt: readDate(d['expiresAt']),
      attempts: (d['attempts'] as num?)?.toInt() ?? 0,
      sendTimes: (d['sendTimes'] is List)
          ? (d['sendTimes'] as List).map(readDate).whereType<DateTime>().toList()
          : const [],
      pending: (d['pending'] is Map)
          ? {
              for (final e in (d['pending'] as Map).entries)
                if (e.key is String && e.value is String) e.key as String: e.value as String,
            }
          : const {},
    );
  }

  static Map<String, Object?> toData(OtpChallenge c) => {
        'codeHash': c.codeHash,
        'salt': c.salt,
        'expiresAt': c.expiresAt?.toUtc(),
        'attempts': c.attempts,
        'sendTimes': c.sendTimes.map((t) => t.toUtc()).toList(),
        'pending': c.pending,
      };

  Future<Map<String, dynamic>?> _doc(String key) => _store.run(_name, (c) => c.findOne(where.eq('_id', key)));

  @override
  Future<OtpChallenge?> read(String key) async => fromData(await _doc(key));

  @override
  Future<OtpChallenge> update(String key, OtpChallenge Function(OtpChallenge? current) mutate) async {
    for (var attempt = 0; attempt < maxWriteAttempts; attempt++) {
      await backoff(attempt);
      final doc = await _doc(key);
      final next = mutate(fromData(doc));
      if (doc == null) {
        final result = await _store.run(_name, (c) => c.insertOne({'_id': key, ...toData(next), 'v': 0}));
        if (!MongoStore.isDuplicate(result)) return next;
      } else {
        final result = await _store.run(
          _name,
          (c) => c.modernFindAndModify(
            query: where.eq('_id', key).eq('v', (doc['v'] as int?) ?? 0),
            update: setAll(toData(next))..inc('v', 1),
            returnNew: true,
          ),
        );
        if (result.value != null) return next;
      }
    }
    throw StateError('otp_write_conflict');
  }
}

class MongoConfigRepository implements ConfigRepository {
  MongoConfigRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.config;

  @override
  Future<CampusConfig?> read() async {
    final d = await _store.run(_name, (c) => c.findOne(where.eq('_id', 'app')));
    if (d == null) return null;
    return CampusConfig(
      campusName: (d['campusName'] as String?) ?? '',
      hotline: readString(d['hotline']),
      buildings: readStringList(d['buildings']),
      updatedAt: readDate(d['updatedAt']),
    );
  }

  @override
  Future<CampusConfig> write(CampusConfig config) async {
    await _store.run(
      _name,
      (c) => c.updateOne(
        where.eq('_id', 'app'),
        setAll({
          'campusName': config.campusName,
          'hotline': config.hotline,
          'buildings': config.buildings,
          'updatedAt': (config.updatedAt ?? DateTime.now()).toUtc(),
        }),
        upsert: true,
      ),
    );
    return config;
  }
}

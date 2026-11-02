import 'package:mongo_dart/mongo_dart.dart' show where;

import '../safety/broadcast_service.dart';
import '../safety/walk_service.dart';
import 'mongo_repositories.dart';
import 'mongo_store.dart';

/// Cảnh báo toàn trường (collection `broadcasts`).
class MongoBroadcastRepository implements BroadcastRepository {
  MongoBroadcastRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.broadcasts;

  static BroadcastRecord? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    return BroadcastRecord(
      id: d['_id'] as String,
      title: (d['title'] as String?) ?? '',
      body: (d['body'] as String?) ?? '',
      level: BroadcastLevel.tryFromWire(d['level'] as String?) ?? BroadcastLevel.info,
      createdAt: readDate(d['createdAt']) ?? DateTime.now().toUtc(),
      expiresAt: readDate(d['expiresAt']) ?? DateTime.now().toUtc(),
      createdByUid: (d['createdByUid'] as String?) ?? '',
      createdByName: (d['createdByName'] as String?) ?? '',
      active: d['active'] == true,
      endedAt: readDate(d['endedAt']),
    );
  }

  @override
  String newId() => newDocumentId();

  @override
  Future<void> create(BroadcastRecord r) async {
    final result = await _store.run(
      _name,
      (c) => c.insertOne({
        '_id': r.id,
        'title': r.title,
        'body': r.body,
        'level': r.level.wire,
        'active': r.active,
        'createdAt': r.createdAt.toUtc(),
        'expiresAt': r.expiresAt.toUtc(),
        'createdByUid': r.createdByUid,
        'createdByName': r.createdByName,
        'endedAt': null,
      }),
    );
    if (!result.isSuccess) throw StateError('insert_broadcast_failed');
  }

  @override
  Future<BroadcastRecord?> byId(String id) async => fromDoc(await _store.run(_name, (c) => c.findOne(where.eq('_id', id))));

  @override
  Future<void> end(String id, DateTime at) async {
    await _store.run(_name, (c) => c.updateOne(where.eq('_id', id), setAll({'active': false, 'endedAt': at.toUtc()})));
  }

  @override
  Future<List<BroadcastRecord>> recent({required int limit}) async {
    final docs = await _store.run(_name, (c) => c.find(where.sortBy('createdAt', descending: true).limit(limit)).toList());
    return docs.map(fromDoc).whereType<BroadcastRecord>().toList();
  }
}

/// Lượt "Đi cùng tôi" (collection `walks`).
class MongoWalkRepository implements WalkRepository {
  MongoWalkRepository(this._store);

  final MongoStore _store;

  static const _name = Collections.walks;

  static WalkRecord? fromDoc(Map<String, dynamic>? d) {
    if (d == null) return null;
    final uid = d['uid'];
    final started = readDate(d['startedAt']);
    final due = readDate(d['dueAt']);
    if (uid is! String || started == null || due == null) return null;
    return WalkRecord(
      id: d['_id'] as String,
      uid: uid,
      displayName: (d['displayName'] as String?) ?? '',
      phone: readString(d['phone']),
      destination: (d['destination'] as String?) ?? '',
      startedAt: started,
      dueAt: due,
      status: WalkStatus.fromWire(d['status'] as String?),
      updatedAt: readDate(d['updatedAt']) ?? started,
      lastLatitude: readDouble(d['lastLatitude']),
      lastLongitude: readDouble(d['lastLongitude']),
      lastAccuracy: readDouble(d['lastAccuracy']),
      lastLocationAt: readDate(d['lastLocationAt']),
      reportId: readString(d['reportId']),
      endedAt: readDate(d['endedAt']),
    );
  }

  static Map<String, Object?> toDoc(WalkRecord w) => {
        'uid': w.uid,
        'displayName': w.displayName,
        'phone': w.phone,
        'destination': w.destination,
        'startedAt': w.startedAt.toUtc(),
        'dueAt': w.dueAt.toUtc(),
        'status': w.status.wire,
        'updatedAt': w.updatedAt.toUtc(),
        'lastLatitude': w.lastLatitude,
        'lastLongitude': w.lastLongitude,
        'lastAccuracy': w.lastAccuracy,
        'lastLocationAt': w.lastLocationAt?.toUtc(),
        'reportId': w.reportId,
        'endedAt': w.endedAt?.toUtc(),
      };

  Future<Map<String, dynamic>?> _doc(String id) => _store.run(_name, (c) => c.findOne(where.eq('_id', id)));

  @override
  String newId() => newDocumentId();

  @override
  Future<WalkRecord?> byId(String id) async => fromDoc(await _doc(id));

  @override
  Future<WalkRecord?> activeFor(String uid) async => fromDoc(
        await _store.run(_name, (c) => c.findOne(where.eq('uid', uid).eq('status', WalkStatus.active.wire))),
      );

  @override
  Future<List<WalkRecord>> listActive() async {
    final docs = await _store.run(_name, (c) => c.find(where.eq('status', WalkStatus.active.wire)).toList());
    return docs.map(fromDoc).whereType<WalkRecord>().toList();
  }

  @override
  Future<void> save(WalkRecord walk) async {
    await _store.run(
      _name,
      (c) => c.updateOne(where.eq('_id', walk.id), setAll(toDoc(walk))..inc('v', 1), upsert: true),
    );
  }

  @override
  Future<WalkRecord?> updateIfActive(String id, WalkRecord Function(WalkRecord current) update) async {
    for (var attempt = 0; attempt < maxWriteAttempts; attempt++) {
      await backoff(attempt);
      final doc = await _doc(id);
      final current = fromDoc(doc);
      if (current == null || !current.isActive) return null;
      final next = update(current);
      final result = await _store.run(
        _name,
        (c) => c.modernFindAndModify(
          query: where.eq('_id', id).eq('v', (doc!['v'] as int?) ?? 0),
          update: setAll(toDoc(next))..inc('v', 1),
          returnNew: true,
        ),
      );
      if (result.value != null) return next;
    }
    throw StateError('walk_write_conflict');
  }
}

// Chép dữ liệu từ Firestore cũ sang MongoDB. Chỉ đọc Firestore, chạy lại nhiều lần vẫn an toàn
// (ghi đè theo ID). Chạy trong thư mục backend:
//   dart run tool/migrate_firestore_to_mongo.dart
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_firebase_admin/dart_firebase_admin.dart';
import 'package:dart_firebase_admin/firestore.dart';
import 'package:dotenv/dotenv.dart';
import 'package:mongo_dart/mongo_dart.dart' show BsonBinary, where;
import 'package:campus_safety_backend/src/data/mongo_repositories.dart';

/// Đổi `Timestamp` của Firestore thành `DateTime`, kể cả trong map và danh sách lồng nhau.
Object? convert(Object? v) => switch (v) {
      final Timestamp t => DateTime.fromMicrosecondsSinceEpoch(t.seconds * 1000000 + t.nanoseconds ~/ 1000, isUtc: true),
      final Map<Object?, Object?> m => {for (final e in m.entries) '${e.key}': convert(e.value)},
      final List<Object?> l => l.map(convert).toList(),
      _ => v,
    };

Map<String, Object?> plain(Map<String, Object?> d) => (convert(d)! as Map).cast<String, Object?>();

Future<void> main() async {
  final env = DotEnv(quiet: true)..load(['.env']);
  final projectId = env['FIREBASE_PROJECT_ID']!;
  final app = FirebaseAdminApp.initializeApp(projectId, Credential.fromServiceAccount(File(env['GOOGLE_APPLICATION_CREDENTIALS']!)));
  final firestore = Firestore(app);
  final store = await MongoStore.connect(env['MONGODB_URI']!);

  Future<void> put(String collection, String id, Map<String, Object?> doc) async {
    await store.run(collection, (c) => c.updateOne(where.eq('_id', id), setAll(doc), upsert: true));
  }

  Future<int> copy(String collection, [Map<String, Object?> Function(Map<String, Object?> d)? map]) async {
    final docs = (await firestore.collection(collection).get()).docs;
    for (final d in docs) {
      final doc = plain(d.data());
      await put(collection, d.id, map == null ? doc : map(doc));
    }
    print('$collection: ${docs.length}');
    return docs.length;
  }

  try {
    await copy(Collections.users);
    await copy(Collections.credentials);
    await copy(Collections.config);
    await copy(Collections.broadcasts);
    await copy(Collections.walks, (d) => {...d, 'v': 0});
    await copy(Collections.reportImages, (d) {
      final data = d['data'];
      return {...d, if (data is String) 'data': BsonBinary.from(base64Decode(data))};
    });

    final reports = (await firestore.collection(Collections.reports).get()).docs;
    for (final r in reports) {
      final events = (await r.ref.collection('events').orderBy('createdAt').get()).docs.map((e) => plain(e.data())).toList();
      final reporter = (await r.ref.collection('private').doc('reporter').get()).data();
      await put(Collections.reports, r.id, {
        ...plain(r.data()),
        'reporter': reporter == null ? null : plain(reporter),
        'events': events,
        'v': 0,
      });
    }
    print('${Collections.reports}: ${reports.length}');
  } finally {
    await store.close();
    await app.close();
  }
  exit(0);
}

import 'dart:io';

import 'package:dart_firebase_admin/auth.dart' as fb_auth;
import 'package:dart_firebase_admin/dart_firebase_admin.dart';
import 'package:dart_firebase_admin/messaging.dart' as fb_messaging;

import 'auth/firebase_auth_service.dart';
import 'auth/otp_mailer.dart';
import 'auth/account_service.dart';
import 'config/app_config.dart';
import 'data/models.dart';
import 'data/mongo_repositories.dart';
import 'data/mongo_safety_repositories.dart';
import 'data/mongo_store.dart';
import 'data/repositories.dart';
import 'notifications/notification_service.dart';
import 'notifications/push_service.dart';
import 'http/user_limits.dart';
import 'reports/image_store.dart';
import 'reports/report_service.dart';
import 'safety/broadcast_service.dart';
import 'safety/walk_service.dart';

/// Toàn bộ dịch vụ của backend, khởi tạo một lần trong `main.dart` và cung cấp cho route qua
/// `context.read<AppServices>()`.
class AppServices {
  AppServices({
    required this.config,
    required this.users,
    required this.reports,
    required this.campusConfig,
    required this.authTokens,
    required this.accounts,
    required this.reportService,
    required this.notifications,
    required this.broadcasts,
    required this.walks,
    required this.images,
    UserLimits? limits,
    Future<bool> Function()? databaseHealthy,
  })  : limits = limits ?? UserLimits(),
        databaseHealthy = databaseHealthy ?? (() async => true);

  final AppConfig config;
  final UserRepository users;
  final ReportRepository reports;
  final ConfigRepository campusConfig;
  final AuthTokenService authTokens;
  final AccountService accounts;
  final ReportService reportService;
  final NotificationService notifications;
  final BroadcastService broadcasts;
  final WalkService walks;
  final ImageService images;

  /// Giới hạn tần suất thao tác ghi theo tài khoản (chống spam).
  final UserLimits limits;

  /// MongoDB có trả lời không (trang /health).
  final Future<bool> Function() databaseHealthy;

  static AppServices? _instance;

  static AppServices get instance {
    final i = _instance;
    if (i == null) throw StateError('AppServices chưa được khởi tạo (xem main.dart).');
    return i;
  }

  static set instance(AppServices value) => _instance = value;

  /// Cấu hình trường hiện tại (MongoDB), rơi về giá trị trong .env và
  /// `config/campus.json` nếu chưa có.
  Future<CampusConfig> currentCampusConfig() async {
    final stored = await campusConfig.read();
    return CampusConfig(
      campusName: (stored?.campusName.isNotEmpty ?? false) ? stored!.campusName : config.campusName,
      hotline: stored?.hotline ?? config.dutyHotline,
      buildings: (stored?.buildings.isNotEmpty ?? false) ? stored!.buildings : config.defaultBuildings,
      updatedAt: stored?.updatedAt,
    );
  }

  /// Kết nối MongoDB (CSDL chính), Firebase Admin (đăng nhập, thông báo đẩy) và mail theo [config].
  static Future<AppServices> production(AppConfig config) async {
    final credentialPath = config.serviceAccountPath;
    final Credential credential;
    if (credentialPath != null) {
      final file = File(credentialPath);
      if (!file.existsSync()) {
        throw ConfigException([
          'Không tìm thấy file service account "$credentialPath" (GOOGLE_APPLICATION_CREDENTIALS).',
        ]);
      }
      credential = Credential.fromServiceAccount(file);
    } else {
      credential = Credential.fromApplicationDefaultCredentials();
    }
    final app = FirebaseAdminApp.initializeApp(config.firebaseProjectId, credential);
    final store = await MongoStore.connect(config.mongoUri);

    final users = MongoUserRepository(store);
    final reports = MongoReportRepository(store);
    final authTokens = FirebaseAuthTokenService(fb_auth.Auth(app));

    final notifications = NotificationService(
      push: FcmPushService(fb_messaging.Messaging(app)),
      users: users,
    );

    final reportService = ReportService(
      reports: reports,
      users: users,
      notifications: notifications,
      revokeSessions: authTokens.revokeSessions,
    );
    return AppServices(
      databaseHealthy: store.isHealthy,
      config: config,
      users: users,
      reports: reports,
      campusConfig: MongoConfigRepository(store),
      authTokens: authTokens,
      notifications: notifications,
      accounts: AccountService(
        store: MongoOtpStore(store),
        users: users,
        credentials: MongoCredentialRepository(store),
        mailer: config.mailScriptUrl != null
            ? AppsScriptOtpMailer(
                url: config.mailScriptUrl!,
                secret: config.mailScriptSecret!,
                fromName: config.mailFromName,
                appName: config.mailFromName,
              )
            : SmtpOtpMailer(
                host: config.smtpHost,
                port: config.smtpPort,
                username: config.smtpUsername,
                password: config.smtpPassword,
                fromName: config.mailFromName,
                appName: config.mailFromName,
              ),
        auth: authTokens,
        pepper: config.otpPepper,
        allowSelfRegistration: config.allowSelfRegistration,
        bootstrapAdmins: config.bootstrapAdminEmails,
      ),
      reportService: reportService,
      images: ImageService(MongoImageRepository(store)),
      broadcasts: BroadcastService(broadcasts: MongoBroadcastRepository(store), notifications: notifications),
      walks: WalkService(
        walks: MongoWalkRepository(store),
        users: users,
        reports: reportService,
        notifications: notifications,
      ),
    );
  }
}

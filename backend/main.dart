import 'dart:async';
import 'dart:io';

import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;

/// Chạy một lần khi khởi động: đọc .env, kiểm tra cấu hình, kết nối Firebase Admin và mail.
Future<void> init(InternetAddress ip, int port) async {
  final fileEnv = DotEnv(quiet: true);
  if (File('.env').existsSync()) fileEnv.load(['.env']);
  // Biến môi trường của hệ thống (Cloud Run, Docker) ưu tiên hơn file .env.
  final env = <String, String>{
    for (final key in AppConfig.knownKeys)
      if ((Platform.environment[key] ?? fileEnv[key]) case final String value) key: value,
  };

  final AppConfig config;
  try {
    config = AppConfig.fromEnvironment(env, defaultBuildings: AppConfig.loadDefaultBuildings());
  } on ConfigException catch (e) {
    stderr.writeln(e);
    stderr.writeln('Sao chép backend/.env.example thành backend/.env và điền đủ các giá trị trên.');
    exit(78); // EX_CONFIG
  }

  final services = await AppServices.production(config);
  AppServices.instance = services;
  services.walks.startOverdueTimer();
  _keepAwakeOnRender();
  stdout.writeln(
    config.mailScriptUrl != null
        ? '[campus_safety] OTP gửi qua Google Apps Script.'
        : '[campus_safety] OTP gửi qua email ${config.smtpUsername} (${config.smtpHost}:${config.smtpPort}).',
  );
}

/// Render miễn phí cho máy chủ ngủ sau 15 phút không có truy cập từ ngoài, khi đó quét quá giờ
/// "Đi cùng tôi" cũng dừng. Tự gọi địa chỉ công khai định kỳ để máy chủ luôn thức.
void _keepAwakeOnRender() {
  final url = Platform.environment['RENDER_EXTERNAL_URL'];
  if (url == null || url.isEmpty) return;
  Timer.periodic(const Duration(minutes: 10), (_) async {
    try {
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      stderr.writeln('[keep-awake] $e');
    }
  });
}

Future<HttpServer> run(Handler handler, InternetAddress ip, int port) {
  return serve(handler, ip, port);
}

import 'dart:convert';
import 'dart:io';

import 'package:campus_core/campus_core.dart';

class ConfigException implements Exception {
  ConfigException(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'Cấu hình backend chưa đúng (.env):\n${problems.map((p) => '  - $p').join('\n')}';
}

/// Toàn bộ cấu hình đọc từ `.env` / biến môi trường.
class AppConfig {
  AppConfig({
    required this.mongoUri,
    required this.firebaseProjectId,
    required this.serviceAccountPath,
    required this.otpPepper,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpUsername,
    required this.smtpPassword,
    required this.mailScriptUrl,
    required this.mailScriptSecret,
    required this.mailFromName,
    required this.allowSelfRegistration,
    required this.bootstrapAdminEmails,
    required this.dutyHotline,
    required this.campusName,
    required this.defaultBuildings,
    required this.trustProxy,
  });

  /// Chuỗi kết nối MongoDB (CSDL chính). Có chứa mật khẩu, không ghi ra log.
  final String mongoUri;
  final String firebaseProjectId;
  final String? serviceAccountPath;
  final String otpPepper;

  /// Máy chủ gửi email OTP (mặc định Gmail).
  final String smtpHost;
  final int smtpPort;
  final String smtpUsername;
  final String smtpPassword;

  /// Web app Google Apps Script gửi mail qua HTTPS. Có giá trị thì dùng thay SMTP.
  final String? mailScriptUrl;
  final String? mailScriptSecret;
  final String mailFromName;
  final bool allowSelfRegistration;
  final Set<EmailAddress> bootstrapAdminEmails;

  final String? dutyHotline;
  final String campusName;
  final List<String> defaultBuildings;
  final bool trustProxy;

  /// Mọi biến cấu hình backend đọc (xem `.env.example`).
  static final List<String> knownKeys = [
    'MONGODB_URI',
    'FIREBASE_PROJECT_ID',
    'GOOGLE_APPLICATION_CREDENTIALS',
    'OTP_PEPPER',
    'SMTP_HOST',
    'SMTP_PORT',
    'SMTP_USERNAME',
    'SMTP_PASSWORD',
    'MAIL_SCRIPT_URL',
    'MAIL_SCRIPT_SECRET',
    'MAIL_FROM_NAME',
    'ALLOW_SELF_REGISTRATION',
    'BOOTSTRAP_ADMIN_EMAILS',
    'DUTY_HOTLINE',
    'CAMPUS_NAME',
    'TRUST_PROXY',
  ];

  /// Đọc cấu hình từ [env]. Ném [ConfigException] liệt kê mọi lỗi cùng lúc.
  factory AppConfig.fromEnvironment(
    Map<String, String> env, {
    List<String> defaultBuildings = const [],
  }) {
    final problems = <String>[];

    String? read(String key) {
      final v = env[key]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    String requireKey(String key, String hint) {
      final v = read(key);
      if (v == null) problems.add('Thiếu $key: $hint');
      return v ?? '';
    }

    bool readBool(String key, {required bool fallback}) {
      final v = read(key)?.toLowerCase();
      if (v == null) return fallback;
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
      problems.add('$key phải là true hoặc false (đang là "$v").');
      return fallback;
    }

    List<EmailAddress> readEmails(String key) {
      final raw = read(key);
      if (raw == null) return const [];
      final result = <EmailAddress>[];
      for (final part in raw.split(RegExp(r'[,;]'))) {
        if (part.trim().isEmpty) continue;
        try {
          result.add(EmailAddress.parse(part));
        } on EmailFormatException catch (e) {
          problems.add('$key có email không hợp lệ "${part.trim()}": ${e.message}');
        }
      }
      return result;
    }

    final mongoUri = requireKey('MONGODB_URI', 'Chuỗi kết nối MongoDB, ví dụ mongodb+srv://user:matkhau@cum.mongodb.net/an_ninh.');
    if (mongoUri.isNotEmpty && !mongoUri.startsWith('mongodb')) {
      problems.add('MONGODB_URI phải bắt đầu bằng mongodb:// hoặc mongodb+srv://.');
    }

    final projectId = requireKey('FIREBASE_PROJECT_ID', 'Project ID của Firebase.');

    final pepper = requireKey('OTP_PEPPER', 'Chuỗi bí mật >= 32 ký tự để băm OTP.');
    if (pepper.isNotEmpty && pepper.length < 32) {
      problems.add('OTP_PEPPER phải dài ít nhất 32 ký tự.');
    }

    final mailScriptUrl = read('MAIL_SCRIPT_URL');
    final mailScriptSecret = read('MAIL_SCRIPT_SECRET');
    final useScript = mailScriptUrl != null;
    if (useScript) {
      if (!mailScriptUrl.startsWith('https://')) problems.add('MAIL_SCRIPT_URL phải bắt đầu bằng https://.');
      if ((mailScriptSecret?.length ?? 0) < 32) problems.add('MAIL_SCRIPT_SECRET phải dài ít nhất 32 ký tự.');
    }
    String requireSmtp(String key, String hint) => useScript ? (read(key) ?? '') : requireKey(key, hint);

    final smtpUser = requireSmtp('SMTP_USERNAME', 'Địa chỉ Gmail dùng để gửi mã OTP (hoặc đặt MAIL_SCRIPT_URL).');
    if (smtpUser.isNotEmpty && EmailAddress.tryParse(smtpUser) == null) {
      problems.add('SMTP_USERNAME phải là địa chỉ email (đang là "$smtpUser").');
    }
    // Mật khẩu ứng dụng Gmail hiển thị dạng "abcd efgh ijkl mnop": bỏ khoảng trắng.
    final smtpPassword = requireSmtp(
      'SMTP_PASSWORD',
      'Mật khẩu ứng dụng của Gmail (myaccount.google.com/apppasswords), không phải mật khẩu đăng nhập.',
    ).replaceAll(' ', '');
    final portRaw = read('SMTP_PORT');
    final smtpPort = portRaw == null ? 587 : int.tryParse(portRaw);
    if (smtpPort == null || smtpPort <= 0 || smtpPort > 65535) {
      problems.add('SMTP_PORT phải là số cổng hợp lệ, thường là 587 hoặc 465 (đang là "$portRaw").');
    }

    final hotlineRaw = read('DUTY_HOTLINE');
    if (hotlineRaw != null && !RegExp(r'^[0-9+ ().-]{3,20}$').hasMatch(hotlineRaw)) {
      problems.add('DUTY_HOTLINE không hợp lệ.');
    }

    final config = AppConfig(
      mongoUri: mongoUri,
      firebaseProjectId: projectId,
      serviceAccountPath: read('GOOGLE_APPLICATION_CREDENTIALS'),
      otpPepper: pepper,
      smtpHost: read('SMTP_HOST') ?? 'smtp.gmail.com',
      smtpPort: smtpPort ?? 587,
      smtpUsername: smtpUser,
      smtpPassword: smtpPassword,
      mailScriptUrl: mailScriptUrl,
      mailScriptSecret: mailScriptSecret,
      mailFromName: read('MAIL_FROM_NAME') ?? 'An ninh trường học',
      allowSelfRegistration: readBool('ALLOW_SELF_REGISTRATION', fallback: true),
      bootstrapAdminEmails: readEmails('BOOTSTRAP_ADMIN_EMAILS').toSet(),
      dutyHotline: hotlineRaw,
      campusName: read('CAMPUS_NAME') ?? 'Trường Đại học',
      defaultBuildings: defaultBuildings,
      trustProxy: readBool('TRUST_PROXY', fallback: false),
    );
    if (problems.isNotEmpty) throw ConfigException(problems);
    return config;
  }

  /// Đọc danh sách khu vực mặc định từ `config/campus.json`.
  static List<String> loadDefaultBuildings([String path = 'config/campus.json']) {
    final file = File(path);
    if (!file.existsSync()) return const [];
    final json = jsonDecode(file.readAsStringSync());
    if (json is! Map || json['buildings'] is! List) return const [];
    return (json['buildings'] as List).whereType<String>().toList();
  }
}

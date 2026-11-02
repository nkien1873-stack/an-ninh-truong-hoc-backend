import 'dart:convert';
import 'dart:math';

/// In ra chuỗi ngẫu nhiên 48 byte (base64url) để dùng làm OTP_PEPPER.
///   dart run tool/generate_secret.dart
void main() {
  final random = Random.secure();
  final bytes = List<int>.generate(48, (_) => random.nextInt(256));
  print(base64Url.encode(bytes).replaceAll('=', ''));
}

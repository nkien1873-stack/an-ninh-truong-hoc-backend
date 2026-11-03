import 'dart:convert';

/// Trang giới thiệu khi mở địa chỉ API bằng trình duyệt (app vẫn nhận JSON ở cùng địa chỉ).
String landingPageHtml({required bool databaseOk, required String campusName}) {
  final esc = const HtmlEscape();
  final status = databaseOk
      ? '<span class="ok">đang chạy, cơ sở dữ liệu kết nối tốt</span>'
      : '<span class="bad">đang chạy, nhưng chưa kết nối được cơ sở dữ liệu</span>';
  const rows = [
    ('Ngôn ngữ / framework', 'Dart + Dart Frog'),
    ('Cơ sở dữ liệu chính', 'MongoDB Atlas (cụm Hồng Kông)'),
    ('Dịch vụ hỗ trợ', 'Firebase: chỉ đăng nhập (custom token) và thông báo đẩy FCM; không lưu dữ liệu nghiệp vụ'),
    ('Máy chủ', 'Render, đóng gói Docker (tự triển khai lại khi đẩy code lên GitHub)'),
    ('Gửi mã OTP', 'Gmail qua Google Apps Script'),
    ('Bảo mật', 'Mật khẩu băm PBKDF2-HMAC-SHA256, OTP lưu dạng HMAC, đăng nhập bằng Firebase ID token (Bearer), '
        'phân quyền người báo / bảo vệ / quản trị, báo cáo ẩn danh thật, giới hạn tần suất'),
    ('Dữ liệu trả về', 'JSON; lỗi trả về dạng {"error": {"code", "message"}} kèm mã HTTP'),
  ];
  final table = rows
      .map((r) => '<tr><th>${esc.convert(r.$1)}</th><td>${esc.convert(r.$2)}</td></tr>')
      .join();
  return '''<!doctype html>
<html lang="vi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>An ninh trường học API</title>
<style>
  :root { --brand: #1d4ea6; --bg: #f3f5f9; --card: #fff; --text: #1a1f2b; --muted: #5b6475; --line: #dde2ea; }
  @media (prefers-color-scheme: dark) {
    :root { --brand: #1b3f86; --bg: #11141a; --card: #1a1f27; --text: #e6e9ef; --muted: #9aa3b2; --line: #2c333f; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); }
  header { background: var(--brand); color: #fff; padding: 32px 24px; }
  header h1 { margin: 0 0 8px; font-size: 30px; }
  header p { margin: 0 0 16px; opacity: .9; }
  .pill { display: inline-block; padding: 8px 14px; border-radius: 999px; background: rgba(255,255,255,.15); }
  .ok { color: #9cf0b8; font-weight: 600; }
  .bad { color: #ffb4a8; font-weight: 600; }
  main { max-width: 960px; margin: 0 auto; padding: 24px; }
  h2 { font-size: 20px; margin: 24px 0 12px; }
  .links { display: flex; flex-wrap: wrap; gap: 10px; }
  .links a, .links span { padding: 10px 16px; border: 1px solid var(--line); border-radius: 10px; background: var(--card);
    color: var(--brand); text-decoration: none; }
  @media (prefers-color-scheme: dark) { .links a { color: #9ec0ff; } }
  .links span { color: var(--muted); }
  .links a:hover { border-color: var(--brand); }
  table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); border-radius: 12px; overflow: hidden; }
  th, td { text-align: left; vertical-align: top; padding: 12px 16px; border-bottom: 1px solid var(--line); }
  th { width: 30%; font-weight: 500; color: var(--muted); }
  tr:last-child th, tr:last-child td { border-bottom: 0; }
  footer { color: var(--muted); font-size: 14px; margin-top: 24px; }
  footer a { color: var(--brand); }
  @media (prefers-color-scheme: dark) { footer a { color: #9ec0ff; } }
  code { font-family: ui-monospace, Consolas, monospace; }
</style>
</head>
<body>
<header>
  <h1>An ninh trường học API</h1>
  <p>Backend của ứng dụng báo cáo sự cố an ninh trong trường (Flutter), nhóm CodeAndChill${campusName.isEmpty ? '' : ' · ${esc.convert(campusName)}'}</p>
  <div class="pill">Trạng thái: $status</div>
</header>
<main>
  <h2>Thử nhanh (bấm để xem dữ liệu thật)</h2>
  <div class="links">
    <a href="/health">/health: tình trạng máy chủ và cơ sở dữ liệu</a>
    <a href="/config">/config: tên trường, số trực, danh sách khu vực</a>
    <span>/reports, /walks, /admin/*: cần đăng nhập</span>
  </div>
  <h2>Công nghệ</h2>
  <table>$table</table>
  <footer>Mã nguồn: <a href="https://github.com/nkien1873-stack/an-ninh-truong-hoc-backend">backend</a> ·
    <a href="https://github.com/nkien1873-stack/an-ninh-truong-hoc-app">app Flutter</a>.
    App gọi cùng địa chỉ này và nhận JSON, ví dụ <code>GET /</code> trả về <code>{"ok":true}</code>.</footer>
</main>
</body>
</html>''';
}

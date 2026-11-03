import 'package:campus_safety_backend/backend.dart';
import 'package:test/test.dart';

void main() {
  test('trang giới thiệu: trạng thái cơ sở dữ liệu, nút thử nhanh, công nghệ', () {
    final ok = landingPageHtml(databaseOk: true, campusName: 'Trường Đại học');
    expect(ok, contains('cơ sở dữ liệu kết nối tốt'));
    expect(ok, contains('href="/health"'));
    expect(ok, contains('href="/config"'));
    expect(ok, contains('MongoDB Atlas'));
    expect(ok, contains('Trường Đại học'));

    final down = landingPageHtml(databaseOk: false, campusName: '');
    expect(down, contains('chưa kết nối được cơ sở dữ liệu'));
  });

  test('tên trường do quản trị nhập được thoát ký tự HTML', () {
    final html = landingPageHtml(databaseOk: true, campusName: '<script>alert(1)</script>');
    expect(html, isNot(contains('<script>alert(1)</script>')));
    expect(html, contains('&lt;script&gt;'));
  });
}

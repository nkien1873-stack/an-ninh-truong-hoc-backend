# Chạy backend trên laptop này để thử khi sửa code. Dữ liệu nằm trên MongoDB Atlas.
# Cách dùng: chuột phải file này > "Run with PowerShell", hoặc trong PowerShell:
#   powershell -ExecutionPolicy Bypass -File .\chay-backend.ps1
# Giữ cửa sổ này mở trong suốt buổi báo cáo; đóng cửa sổ là tắt backend.

$ErrorActionPreference = 'Stop'

# ---- Tìm Flutter SDK (đã có trong PATH, hoặc các chỗ cài thường gặp) ----
function Find-FlutterBin {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return Split-Path $cmd.Source }
    $candidates = @(
        "$env:FLUTTER_ROOT\bin",
        'C:\flutter\bin', 'C:\src\flutter\bin', 'D:\flutter\bin', 'D:\src\flutter\bin',
        "$env:USERPROFILE\flutter\bin", "$env:USERPROFILE\Documents\flutter\bin",
        "$env:LOCALAPPDATA\flutter\bin"
    ) + (Get-ChildItem 'C:\', 'D:\', "$env:USERPROFILE\Downloads", 'D:\Downloads' -Directory -Filter 'flutter*' -ErrorAction SilentlyContinue |
        ForEach-Object { "$($_.FullName)\bin", "$($_.FullName)\flutter\bin" })
    foreach ($c in $candidates) { if ($c -and (Test-Path "$c\flutter.bat")) { return $c } }
    return $null
}

$flutterBin = Find-FlutterBin
if (-not $flutterBin) {
    Write-Host 'Không tìm thấy Flutter. Nhập đường dẫn thư mục bin của Flutter (vd: C:\flutter\bin):' -ForegroundColor Yellow
    $flutterBin = Read-Host
    if (-not (Test-Path "$flutterBin\flutter.bat")) { throw "Không có flutter.bat trong $flutterBin" }
}
$env:PATH = "$flutterBin;$env:LOCALAPPDATA\Pub\Cache\bin;$env:PATH"
Write-Host "Flutter: $flutterBin"

Set-Location (Join-Path $PSScriptRoot 'backend')
foreach ($f in '.env', 'service-account.json') {
    if (-not (Test-Path $f)) { throw "Thiếu backend\$f. Xin file này từ trưởng nhóm rồi chạy lại." }
}

# ---- Cổng 8080 đang bận thì báo rõ thay vì lỗi khó hiểu ----
$busy = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    Write-Host 'Cổng 8080 đang được dùng: có thể backend đã chạy ở một cửa sổ khác. Đóng cửa sổ đó rồi chạy lại.' -ForegroundColor Yellow
    Read-Host 'Nhấn Enter để thoát'
    exit 1
}

# ---- Build khi chưa có bản build, hoặc khi source mới hơn bản build ----
function Test-NeedBuild {
    $built = 'build\bin\server.dart'
    if (-not (Test-Path $built)) { return $true }
    $builtAt = (Get-Item $built).LastWriteTime
    $sources = Get-ChildItem -Recurse -File 'lib', 'routes', '..\packages\campus_core\lib', 'main.dart', 'pubspec.yaml'
    return [bool]($sources | Where-Object { $_.LastWriteTime -gt $builtAt } | Select-Object -First 1)
}

if (Test-NeedBuild) {
    if (-not (Get-Command dart_frog -ErrorAction SilentlyContinue)) {
        Write-Host 'Đang cài dart_frog_cli...'
        dart pub global activate dart_frog_cli
    }
    Write-Host 'Đang tải thư viện và build backend (vài phút, đừng đóng cửa sổ)...'
    dart pub get
    dart_frog build
    Push-Location build; dart pub get; Pop-Location
}

$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -match 'Wi-Fi|WLAN|Ethernet' -and $_.IPAddress -notlike '169.254*' } |
    Select-Object -ExpandProperty IPAddress
Write-Host ''
Write-Host '=============================================================='
if ($ips) {
    foreach ($ip in $ips) { Write-Host "  Địa chỉ máy chủ cho điện thoại:  $($ip):8080" -ForegroundColor Green }
} else {
    Write-Host '  Chưa có mạng. Kết nối Wi-Fi (hoặc hotspot) rồi chạy lại.' -ForegroundColor Yellow
}
Write-Host '  Điện thoại cùng Wi-Fi với laptop này. Trong app: màn đăng nhập >'
Write-Host '  biểu tượng máy chủ góc phải > nhập địa chỉ trên > Kiểm tra > Lưu.'
Write-Host '  Lần đầu Windows hỏi tường lửa: chọn Cho phép (Allow access).'
Write-Host '=============================================================='
Write-Host ''

dart build\bin\server.dart

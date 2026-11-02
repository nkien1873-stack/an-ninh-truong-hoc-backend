# An ninh trường học: backend web API

Đề tài môn Lập trình di động, nhóm **CodeAndChill** (HUTECH). Đây là phần **backend (web API)** mà app Flutter gọi tới.

| Phần | Kho mã |
|---|---|
| Backend web API (kho này) | https://github.com/nkien1873-stack/an-ninh-truong-hoc-backend |
| App Flutter (frontend) | https://github.com/nkien1873-stack/an-ninh-truong-hoc-app |
| Web API đã triển khai | https://an-ninh-truong-hoc-api.onrender.com |
| Mã nguồn đầy đủ (app + backend trong một kho) | https://github.com/nkien1873-stack/an-ninh-truong-hoc |

## Công nghệ

- **Dart Frog**: web API, mỗi file trong `backend/routes/` là một đường dẫn API.
- **MongoDB Atlas**: cơ sở dữ liệu chính (tài khoản, báo cáo, lượt "Đi cùng tôi", cảnh báo, ảnh).
- **Firebase**: chỉ hỗ trợ đăng nhập (custom token) và gửi thông báo đẩy (FCM).
- **Gmail qua Google Apps Script**: gửi mã OTP đăng ký và quên mật khẩu.
- **Docker + Render**: đóng gói và triển khai lên Internet (`Dockerfile`, `render.yaml`).

## Cấu trúc

```
backend/routes/        các API (auth, me, reports, walks, broadcasts, admin, images, config)
backend/lib/src/       nghiệp vụ: tài khoản, báo cáo, Đi cùng tôi, cảnh báo toàn trường, thông báo, MongoDB
backend/test/          kiểm thử backend
packages/campus_core/  logic dùng chung với app: vai trò, phân quyền, máy trạng thái, kiểm tra dữ liệu
Dockerfile, render.yaml  build và triển khai lên Render
```

`packages/campus_core` là bản sao của package dùng chung trong kho app, để kho này tự build được một mình.

## Một số API

`POST /auth/register/request|verify`, `POST /auth/login`, `POST /auth/password/forgot|reset`, `GET|PATCH /me`,
`GET|POST /reports`, `GET /reports/{id}`, `POST /reports/{id}/status|assign|comments|cancel`, `GET|POST /walks`,
`POST /walks/{id}/location|arrive|cancel|extend|sos`, `GET /broadcasts`, `GET|POST /admin/users`,
`PATCH|DELETE /admin/users/{uid}`, `PUT /admin/config`, `POST /admin/broadcasts`, `GET /config`.

## Chạy trên máy

```bash
cd backend
cp .env.example .env      # điền MONGODB_URI, FIREBASE_PROJECT_ID, OTP_PEPPER, thông tin gửi mail
dart pub get
dart_frog dev             # http://localhost:8080
dart test                 # kiểm thử
```

Khoá bí mật (`backend/.env`, `backend/service-account.json`) không nằm trong kho mã; trên Render chúng được khai báo
ở phần Environment và Secret Files.

# Build backend (dart_frog) cho Render. Ngữ cảnh build là thư mục gốc dự án
# vì backend phụ thuộc packages/campus_core.
FROM dart:stable AS build

WORKDIR /app
COPY packages/campus_core packages/campus_core
COPY backend backend

WORKDIR /app/backend
RUN dart pub global activate dart_frog_cli
RUN dart pub get
RUN dart pub global run dart_frog_cli:dart_frog build

WORKDIR /app/backend/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

# Ảnh chạy tối giản: chỉ có file thực thi, thư viện hệ thống và config/buildings.
FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/backend/build/bin/server /app/bin/server
COPY --from=build /app/backend/config /app/config
WORKDIR /app
CMD ["/app/bin/server"]

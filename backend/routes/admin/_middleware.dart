import 'package:campus_core/campus_core.dart';
import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

/// Mọi route /admin/* chỉ dành cho quản trị.
Handler middleware(Handler handler) => handler.use(requireAuth(roles: {UserRole.admin}));

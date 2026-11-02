import 'package:campus_safety_backend/backend.dart';
import 'package:dart_frog/dart_frog.dart';

Handler middleware(Handler handler) => handler.use(requireAuth());

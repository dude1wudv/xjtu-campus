import 'auth_user.dart';

/// CAS 登录抽象。骨架使用 [MockAuthRepository]。
///
/// 后续实现 `CasAuthRepository`：
/// 1. 打开 / 嵌入 login.xjtu.edu.cn 官方登录流程（含验证码由用户完成）；
/// 2. 仅保存会话 Cookie / TGT，不记录明文密码；
/// 3. 用该会话访问 ehall / 一网通办的课表与通知接口。
abstract class AuthRepository {
  Future<AuthUser?> restoreSession();

  Future<AuthUser> login({
    required String studentId,
    required String password,
  });

  Future<void> logout();
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

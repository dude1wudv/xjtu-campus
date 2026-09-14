import 'dart:typed_data';

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/storage/credential_store.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// 本地模拟登录：任意学号即可体验，密码不会写入存储或日志。
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._store);

  final CredentialStore _store;

  @override
  Future<AuthUser?> restoreSession() async {
    final mode = await _store.read(AppConstants.sessionModeKey);
    if (mode != null && mode != AppConstants.modeDemo) return null;
    final studentId = await _store.read(AppConstants.sessionStudentIdKey);
    final token = await _store.read(AppConstants.sessionTokenKey);
    final name = await _store.read(AppConstants.sessionDisplayNameKey);
    if (studentId == null || studentId.isEmpty || token == null) {
      return null;
    }
    return AuthUser(
      studentId: studentId,
      displayName: name ?? '同学 $studentId',
      sessionToken: token,
      college: '演示会话',
      isDemo: true,
    );
  }

  @override
  Future<AuthUser> login({
    required String studentId,
    required String password,
    String captcha = '',
    String? mfaCode,
    String? accountLabel,
    bool demo = false,
  }) async {
    final id = studentId.trim();
    if (id.isEmpty) {
      throw const AuthException('请输入学号');
    }
    if (password.isEmpty) {
      throw const AuthException('请输入密码');
    }

    final user = AuthUser(
      studentId: id,
      displayName: '同学 $id',
      sessionToken: 'mock-session-$id',
      college: '演示会话',
      isDemo: true,
    );

    await _store.write(key: AppConstants.sessionStudentIdKey, value: user.studentId);
    await _store.write(key: AppConstants.sessionTokenKey, value: user.sessionToken);
    await _store.write(
      key: AppConstants.sessionDisplayNameKey,
      value: user.displayName,
    );
    await _store.write(
      key: AppConstants.sessionModeKey,
      value: AppConstants.modeDemo,
    );
    await _store.delete(AppConstants.forbiddenPasswordKey);

    AppLogger.info('演示登录成功，学号末四位 ${_tail(id)}');
    return user;
  }

  @override
  Future<Uint8List> refreshCaptcha() async => Uint8List(0);

  @override
  Future<String> sendMfaSms() async {
    throw const AuthException('演示模式无需短信验证');
  }

  @override
  Future<void> logout() async {
    await _store.deleteAll();
    AppLogger.info('已清除本地演示会话');
  }

  String _tail(String studentId) {
    if (studentId.length <= 4) return '****';
    return studentId.substring(studentId.length - 4);
  }
}

import '../../../core/constants/app_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/storage/credential_store.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// 本地模拟登录：校验非空学号，写入加密存储中的会话令牌。
/// 密码参数只在方法栈内使用，不会写入存储或日志。
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._store);

  final CredentialStore _store;

  @override
  Future<AuthUser?> restoreSession() async {
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
      college: '钱学森书院（模拟）',
    );
  }

  @override
  Future<AuthUser> login({
    required String studentId,
    required String password,
  }) async {
    final id = studentId.trim();
    if (id.isEmpty) {
      throw const AuthException('请输入学号');
    }
    if (password.isEmpty) {
      throw const AuthException('请输入密码');
    }

    // 密码仅用于模拟“有输入”，随后丢弃。真实 CAS 必须走官方页面，禁止在此代填。
    final user = AuthUser(
      studentId: id,
      displayName: '同学 $id',
      sessionToken: 'mock-session-$id',
      college: '钱学森书院（模拟）',
    );

    await _store.write(
      key: AppConstants.sessionStudentIdKey,
      value: user.studentId,
    );
    await _store.write(
      key: AppConstants.sessionTokenKey,
      value: user.sessionToken,
    );
    await _store.write(
      key: AppConstants.sessionDisplayNameKey,
      value: user.displayName,
    );
    await _store.delete(AppConstants.forbiddenPasswordKey);

    AppLogger.info('模拟登录成功，学号末四位 ${_tail(id)}');
    return user;
  }

  @override
  Future<void> logout() async {
    await _store.deleteAll();
    AppLogger.info('已清除本地模拟会话');
  }

  String _tail(String studentId) {
    if (studentId.length <= 4) return '****';
    return studentId.substring(studentId.length - 4);
  }
}

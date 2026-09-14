/// 凭据与会话的本地安全存储抽象。
///
/// 约定：
/// - 仅保存学号、会话令牌 / Cookie（加密后）；
/// - **不要**长期保存学校密码；CAS 握手结束后立即清除；
/// - 实现层不得把 value 打到日志。
abstract class CredentialStore {
  Future<void> write({required String key, required String value});

  Future<String?> read(String key);

  Future<void> delete(String key);

  Future<void> deleteAll();
}

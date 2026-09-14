import '../storage/credential_store.dart';
import 'package:cookie_jar/cookie_jar.dart';

/// 把 cookie_jar 持久化到 [CredentialStore]（加密存储），不写入明文文件。
class SecureCookieStorage implements Storage {
  SecureCookieStorage(this._store);

  final CredentialStore _store;
  static const _prefix = 'cj.';

  @override
  Future<void> init(bool persistSession, bool ignoreExpires) async {}

  @override
  Future<String?> read(String key) => _store.read('$_prefix$key');

  @override
  Future<void> write(String key, String value) {
    return _store.write(key: '$_prefix$key', value: value);
  }

  @override
  Future<void> delete(String key) => _store.delete('$_prefix$key');

  @override
  Future<void> deleteAll(List<String> keys) async {
    for (final key in keys) {
      await _store.delete('$_prefix$key');
    }
  }
}

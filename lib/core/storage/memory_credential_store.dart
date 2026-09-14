import 'credential_store.dart';

/// 进程内存储，用于测试、插件不可用时的回退，以及尚未配置安全存储的桌面端。
class MemoryCredentialStore implements CredentialStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _values.clear();
  }
}

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';
import 'credential_store.dart';
import 'memory_credential_store.dart';

/// 基于 [FlutterSecureStorage] 的实现。
/// 插件失败、超时或 Web 非安全上下文时回退到内存，避免登录按钮一直转圈。
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? storage,
    CredentialStore? fallback,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _fallback = fallback ?? MemoryCredentialStore();

  static const _timeout = Duration(milliseconds: 1500);

  final FlutterSecureStorage _storage;
  final CredentialStore _fallback;
  bool _useFallback = false;

  Future<T> _guard<T>(
    Future<T> Function() secure,
    Future<T> Function() fallback,
  ) async {
    if (_useFallback) return fallback();
    try {
      return await secure().timeout(_timeout);
    } on Object {
      _useFallback = true;
      AppLogger.warn('安全存储不可用或超时，会话仅保存在内存中');
      return fallback();
    }
  }

  @override
  Future<void> write({required String key, required String value}) {
    return _guard<void>(
      () => _storage.write(key: key, value: value),
      () => _fallback.write(key: key, value: value),
    );
  }

  @override
  Future<String?> read(String key) {
    return _guard<String?>(
      () => _storage.read(key: key),
      () => _fallback.read(key),
    );
  }

  @override
  Future<void> delete(String key) {
    return _guard<void>(
      () => _storage.delete(key: key),
      () => _fallback.delete(key),
    );
  }

  @override
  Future<void> deleteAll() {
    return _guard<void>(
      () => _storage.deleteAll(),
      () => _fallback.deleteAll(),
    );
  }
}

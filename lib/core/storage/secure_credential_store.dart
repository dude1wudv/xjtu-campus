import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';
import 'credential_store.dart';
import 'memory_credential_store.dart';

/// 基于 [FlutterSecureStorage] 的实现。
/// 平台插件失败时静默回退到内存，避免在日志中暴露写入内容。
class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore({
    FlutterSecureStorage? storage,
    CredentialStore? fallback,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _fallback = fallback ?? MemoryCredentialStore();

  final FlutterSecureStorage _storage;
  final CredentialStore _fallback;
  bool _useFallback = false;

  @override
  Future<void> write({required String key, required String value}) async {
    if (_useFallback) {
      await _fallback.write(key: key, value: value);
      return;
    }
    try {
      await _storage.write(key: key, value: value);
    } on Object {
      _useFallback = true;
      AppLogger.warn('安全存储不可用，会话仅保存在内存中');
      await _fallback.write(key: key, value: value);
    }
  }

  @override
  Future<String?> read(String key) async {
    if (_useFallback) {
      return _fallback.read(key);
    }
    try {
      return await _storage.read(key: key);
    } on Object {
      _useFallback = true;
      AppLogger.warn('安全存储读取失败，已回退到内存');
      return _fallback.read(key);
    }
  }

  @override
  Future<void> delete(String key) async {
    if (_useFallback) {
      await _fallback.delete(key);
      return;
    }
    try {
      await _storage.delete(key: key);
    } on Object {
      _useFallback = true;
      await _fallback.delete(key);
    }
  }

  @override
  Future<void> deleteAll() async {
    if (_useFallback) {
      await _fallback.deleteAll();
      return;
    }
    try {
      await _storage.deleteAll();
    } on Object {
      _useFallback = true;
      await _fallback.deleteAll();
    }
  }
}

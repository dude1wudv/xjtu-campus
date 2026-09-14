import 'package:flutter/foundation.dart';

/// 应用日志。凭据、Cookie、CAS Ticket 一律不得进入日志。
abstract final class AppLogger {
  static const _secretHints = [
    'password',
    'passwd',
    'secret',
    'token',
    'ticket',
    'cookie',
    'authorization',
    'captcha',
  ];

  static void info(String message) {
    debugPrint('[xjtu] $message');
  }

  static void warn(String message) {
    debugPrint('[xjtu][warn] $message');
  }

  /// 仅记录安全、可公开的调试信息。若误传入疑似密钥字段名，直接丢弃。
  static void debugSafe(String message) {
    final lower = message.toLowerCase();
    for (final hint in _secretHints) {
      if (lower.contains(hint)) {
        debugPrint('[xjtu][redacted] 已拦截可能含凭据的日志');
        return;
      }
    }
    debugPrint('[xjtu] $message');
  }
}

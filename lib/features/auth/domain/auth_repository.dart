import 'dart:typed_data';

import 'auth_user.dart';

/// CAS 登录抽象。默认实现走 login.xjtu.edu.cn；[demo] 仍可走 Mock。
abstract class AuthRepository {
  Future<AuthUser?> restoreSession();

  Future<AuthUser> login({
    required String studentId,
    required String password,
    String captcha = '',
    String? mfaCode,
    String? accountLabel,
    bool demo = false,
  });

  Future<Uint8List> refreshCaptcha();

  /// 调用学校官方短信接口，把验证码发到学生自己绑定的手机。
  Future<String> sendMfaSms();

  /// WebView 完成 CAS 后导入 Cookie。
  Future<AuthUser> completeWebLogin({
    required String studentId,
    required List<({String name, String value, String? domain, String? path})>
        cookies,
  });

  Future<void> logout();
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CaptchaRequiredException extends AuthException {
  CaptchaRequiredException(this.image) : super('请输入图片验证码后重试');

  final Uint8List image;
}

class MfaRequiredException extends AuthException {
  MfaRequiredException({this.maskedPhone})
    : super('学校要求二次验证。请查收绑定手机短信并输入验证码，我们不会绕过此步骤。');

  final String? maskedPhone;
}

class AccountChoice {
  const AccountChoice({required this.name, required this.label});

  final String name;
  final String label;
}

class AccountChoiceRequiredException extends AuthException {
  AccountChoiceRequiredException(this.choices)
    : super('该账号有多个身份，请选择本次使用的身份。');

  final List<AccountChoice> choices;
}

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/campus_urls.dart';
import '../../../core/crypto/rsa_pkcs1.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/campus_session.dart';
import '../../../core/storage/credential_store.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'mock_auth_repository.dart';

/// 西安交大 CAS（login.xjtu.edu.cn）登录。
///
/// 密码仅在内存中 RSA 加密后提交；图形验证码由用户识别；
/// MFA / Safety Verify 走学校官方短信接口，不绕过。
class CasAuthRepository implements AuthRepository {
  CasAuthRepository({
    required this._session,
    required this._store,
    required this._mock,
  });

  final CampusSession _session;
  final CredentialStore _store;
  final MockAuthRepository _mock;

  _PendingCas? _pending;

  @override
  Future<AuthUser?> restoreSession() async {
    await _session.restore();
    final mode = await _store.read(AppConstants.sessionModeKey);
    if (mode == AppConstants.modeDemo) {
      return _mock.restoreSession();
    }
    final studentId = await _store.read(AppConstants.sessionStudentIdKey);
    if (studentId == null || studentId.isEmpty) return null;
    final hasCas = await _session.hasCasCookie();
    if (!hasCas) return null;
    final name = await _store.read(AppConstants.sessionDisplayNameKey);
    return AuthUser(
      studentId: studentId,
      displayName: name ?? '同学 $studentId',
      sessionToken: 'cas-session',
      college: '统一身份认证',
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
    if (demo) {
      return _mock.login(
        studentId: studentId,
        password: password,
        demo: true,
      );
    }

    final id = studentId.trim();
    if (id.isEmpty && _pending == null) {
      throw const AuthException('请输入学号');
    }
    if (password.isEmpty && _pending == null) {
      throw const AuthException('请输入密码');
    }

    _pending ??= await _begin(id, password);

    if (_pending!.accountChoices != null) {
      if (accountLabel == null || accountLabel.isEmpty) {
        throw AccountChoiceRequiredException(_pending!.accountChoices!);
      }
      return _finishAccountChoice(accountLabel);
    }

    if (_pending!.mfaRequired && (mfaCode == null || mfaCode.isEmpty)) {
      throw MfaRequiredException(maskedPhone: _pending!.maskedPhone);
    }

    if (_pending!.mfaRequired && mfaCode != null && mfaCode.isNotEmpty) {
      await _verifyMfa(mfaCode);
      if (_pending!.safetyHtml != null) {
        return _finishSafetyVerify();
      }
    }

    if (_pending!.captchaRequired && captcha.isEmpty) {
      throw CaptchaRequiredException(await refreshCaptcha());
    }

    return _submitLogin(captcha: captcha);
  }

  @override
  Future<Uint8List> refreshCaptcha() async {
    final bytes = await _session.getBytes(CampusUrls.casCaptcha);
    _pending?.captchaRequired = true;
    return bytes;
  }

  @override
  Future<String> sendMfaSms() async {
    final pending = _pending;
    if (pending == null) {
      throw const AuthException('请先提交学号和密码');
    }
    await _ensureMfaGid(pending);
    final response = await _session.post(
      CampusUrls.casMfaSend,
      data: {'gid': pending.gid},
      jsonBody: true,
    );
    final json = _session.tryJson(response);
    if (json == null || json['code'] != 0) {
      throw AuthException(json?['message']?.toString() ?? '发送短信失败');
    }
    AppLogger.info('已通过学校接口发送登录验证码');
    return pending.maskedPhone ?? '已绑定手机';
  }

  @override
  Future<void> logout() async {
    _pending = null;
    await _session.clear();
    await _store.deleteAll();
    AppLogger.info('已退出统一认证会话');
  }

  Future<_PendingCas> _begin(String studentId, String password) async {
    final fp = _fpVisitorId();
    final loginUrl =
        '${CampusUrls.casLogin}?service=${Uri.encodeComponent(CampusUrls.jwxtHome)}';
    final page = await _session.get(loginUrl);
    final html = page.data?.toString() ?? '';
    if (_isSafetyVerify(html)) {
      final pending = _PendingCas(
        studentId: studentId,
        encryptedPassword: rsaEncryptPassword(
          password,
          (await _session.get(CampusUrls.casPublicKey)).data?.toString() ?? '',
        ),
        execution: _extractInput(html, 'execution') ?? '',
        postUrl: page.realUri.toString(),
        fpVisitorId: fp,
      )..safetyHtml = html
        ..safetyPostUrl = page.realUri.toString()
        ..safetyVerify = true
        ..mfaRequired = true
        ..mfaState = _extractInput(html, 'secState') ?? '';
      return pending;
    }

    final execution = _extractInput(html, 'execution');
    if (execution == null) {
      if (!page.realUri.toString().contains('/cas/login')) {
        await _establishDownstreamSessions();
        await _saveProfile(studentId);
        return _PendingCas(
          studentId: studentId,
          encryptedPassword: '',
          execution: '',
          postUrl: page.realUri.toString(),
          fpVisitorId: fp,
        );
      }
      throw const AuthException('无法打开统一认证页面，请检查网络或稍后重试');
    }
    final keyResponse = await _session.get(CampusUrls.casPublicKey);
    final pem = keyResponse.data?.toString() ?? '';
    if (!pem.contains('BEGIN PUBLIC KEY')) {
      throw const AuthException('无法获取学校登录公钥，请检查网络后重试');
    }
    final encrypted = rsaEncryptPassword(password, pem);

    final pending = _PendingCas(
      studentId: studentId,
      encryptedPassword: encrypted,
      execution: execution,
      postUrl: page.realUri.toString(),
      fpVisitorId: fp,
    );

    await _detectMfa(pending);
    return pending;
  }

  Future<void> _detectMfa(_PendingCas pending) async {
    final response = await _session.post(
      CampusUrls.casMfaDetect,
      data: {
        'username': pending.studentId,
        'password': pending.encryptedPassword,
        'fpVisitorId': pending.fpVisitorId,
        'loginType': 'passwordLogin',
      },
      headers: {'Referer': pending.postUrl},
    );
    final json = _session.tryJson(response);
    if (json == null || json['code'] != 0) return;
    final data = json['data'];
    if (data is Map) {
      pending.mfaState = data['state']?.toString() ?? '';
      pending.mfaRequired = data['need'] == true || data['need'] == 'true';
    }
  }

  Future<void> _ensureMfaGid(_PendingCas pending) async {
    if (pending.gid != null) return;
    final initUrl = pending.safetyVerify
        ? CampusUrls.casSecInitPhone
        : CampusUrls.casMfaInitPhone;
    final response = await _session.get(
      initUrl,
      query: {'state': pending.mfaState},
    );
    final json = _session.tryJson(response);
    if (json == null || json['code'] != 0) {
      throw const AuthException('无法读取绑定手机信息，请到学校统一认证网页完成二次验证');
    }
    final data = json['data'];
    if (data is Map) {
      pending.gid = data['gid']?.toString();
      pending.maskedPhone = data['securePhone']?.toString();
    }
  }

  Future<void> _verifyMfa(String code) async {
    final pending = _pending!;
    await _ensureMfaGid(pending);
    final response = await _session.post(
      CampusUrls.casMfaValid,
      data: {'gid': pending.gid, 'code': code},
      jsonBody: true,
    );
    final json = _session.tryJson(response);
    if (json == null || json['code'] != 0) {
      throw AuthException(json?['message']?.toString() ?? '短信验证码不正确');
    }
    final data = json['data'];
    if (data is Map) {
      final status = data['status'];
      if (status != null && status != 2 && status != '2') {
        throw const AuthException('短信验证码不正确');
      }
    }
    pending.mfaRequired = false;
  }

  Future<AuthUser> _submitLogin({required String captcha}) async {
    final pending = _pending!;
    if (pending.encryptedPassword.isEmpty) {
      await _establishDownstreamSessions();
      await _saveProfile(pending.studentId);
      _pending = null;
      return AuthUser(
        studentId: pending.studentId,
        displayName: '同学 ${pending.studentId}',
        sessionToken: 'cas-session',
        college: '统一身份认证',
      );
    }

    final response = await _session.post(
      pending.postUrl,
      data: {
        'username': pending.studentId,
        'password': pending.encryptedPassword,
        'execution': pending.execution,
        '_eventId': 'submit',
        'submit1': 'Login1',
        'fpVisitorId': pending.fpVisitorId,
        'captcha': captcha,
        'currentMenu': '1',
        'failN': '${pending.failCount}',
        'mfaState': pending.mfaState,
        'geolocation': '',
        'trustAgent': pending.mfaState.isEmpty ? '' : 'true',
      },
      headers: {'Referer': pending.postUrl},
    );
    return _processLoginResponse(response.data?.toString() ?? '', response);
  }

  Future<AuthUser> _processLoginResponse(
    String html,
    dynamic response,
  ) async {
    final pending = _pending!;
    final status = response.statusCode as int?;
    final uri = response.realUri as Uri;

    if (status == 401 || _hasLoginError(html)) {
      pending.failCount += 1;
      pending.captchaRequired = pending.failCount >= 3;
      final message = _alertTitle(html) ?? '登录失败，请检查学号、密码或验证码';
      if (pending.captchaRequired) {
        throw CaptchaRequiredException(await refreshCaptcha());
      }
      throw AuthException(message);
    }

    if (_isSafetyVerify(html)) {
      pending.safetyVerify = true;
      pending.mfaRequired = true;
      pending.safetyHtml = html;
      pending.safetyPostUrl = uri.toString();
      pending.mfaState = _extractInput(html, 'secState') ?? pending.mfaState;
      throw MfaRequiredException(maskedPhone: pending.maskedPhone);
    }

    final accounts = _extractAccounts(html);
    if (accounts != null && accounts.isNotEmpty) {
      pending.accountChoices = accounts;
      pending.accountHtml = html;
      throw AccountChoiceRequiredException(accounts);
    }

    await _establishDownstreamSessions();
    await _saveProfile(pending.studentId);
    _pending = null;
    return AuthUser(
      studentId: pending.studentId,
      displayName: '同学 ${pending.studentId}',
      sessionToken: 'cas-session',
      college: '统一身份认证',
    );
  }

  Future<AuthUser> _finishSafetyVerify() async {
    final pending = _pending!;
    final html = pending.safetyHtml;
    if (html == null) {
      throw const AuthException('二次认证状态已失效，请重新登录');
    }
    final response = await _session.post(
      pending.safetyPostUrl ?? pending.postUrl,
      data: {
        'secState': _extractInput(html, 'secState') ?? pending.mfaState,
        'execution': _extractInput(html, 'execution') ?? pending.execution,
        '_eventId': _extractInput(html, '_eventId') ?? 'submit',
        'geolocation': '',
        'fpVisitorId': pending.fpVisitorId,
        'submit': _extractInput(html, 'submit') ?? 'Login1',
      },
    );
    pending.safetyHtml = null;
    pending.safetyVerify = false;
    return _processLoginResponse(response.data?.toString() ?? '', response);
  }

  Future<AuthUser> _finishAccountChoice(String label) async {
    final pending = _pending!;
    final html = pending.accountHtml ?? '';
    final response = await _session.post(
      CampusUrls.casLogin,
      data: {
        'execution': _extractInput(html, 'execution') ?? pending.execution,
        '_eventId': 'submit',
        'geolocation': '',
        'fpVisitorId': pending.fpVisitorId,
        'trustAgent': pending.mfaState.isEmpty ? '' : 'true',
        'username': label,
        'useDefault': 'false',
      },
    );
    pending.accountChoices = null;
    pending.accountHtml = null;
    return _processLoginResponse(response.data?.toString() ?? '', response);
  }

  Future<void> _establishDownstreamSessions() async {
    try {
      await _session.get(CampusUrls.jwxtHome);
    } on Object {
      AppLogger.warn('教务系统单点登录未完成，课表可能需要校园网或 WebVPN');
    }
    try {
      await _session.get(CampusUrls.ehallLogin);
    } on Object {
      AppLogger.warn('ehall 单点登录未完成');
    }
    try {
      final ywtb = await _session.get(CampusUrls.ywtbCasLogin);
      final ticket = ywtb.realUri.queryParameters['ticket'];
      if (ticket != null && ticket.contains('.')) {
        final payload = _jwtPayload(ticket);
        final idToken = payload['idToken']?.toString();
        if (idToken != null) {
          await _session.saveYwtbIdToken(idToken);
        }
      }
    } on Object {
      AppLogger.warn('一网通办单点登录未完成');
    }
  }

  Future<void> _saveProfile(String studentId) async {
    var display = '同学 $studentId';
    try {
      final response = await _session.get(
        CampusUrls.ywtbUser,
        headers: {
          'Referer': CampusUrls.ywtbMain,
          if (_session.ywtbIdToken != null) 'x-id-token': _session.ywtbIdToken!,
          'x-device-info': 'PC',
          'x-terminal-info': 'PC',
        },
      );
      final json = _session.tryJson(response);
      final data = json?['data'];
      if (data is Map) {
        final attributes = data['attributes'];
        if (attributes is Map && attributes['userName'] != null) {
          display = attributes['userName'].toString();
        } else if (data['username'] != null) {
          display = data['username'].toString();
        }
      }
    } on Object {
      // 姓名获取失败不影响登录。
    }

    await _store.write(key: AppConstants.sessionStudentIdKey, value: studentId);
    await _store.write(key: AppConstants.sessionTokenKey, value: 'cas-session');
    await _store.write(key: AppConstants.sessionDisplayNameKey, value: display);
    await _store.write(
      key: AppConstants.sessionModeKey,
      value: AppConstants.modeCas,
    );
    await _store.delete(AppConstants.forbiddenPasswordKey);
    AppLogger.info('CAS 登录成功，学号末四位 ${_tail(studentId)}');
  }

  bool _hasLoginError(String html) {
    return html.contains('el-alert') &&
        (html.contains('type="error"') || html.contains("type='error'"));
  }

  bool _isSafetyVerify(String html) {
    return html.contains('secState') &&
        (html.contains('Safety Verify') ||
            html.contains('二次认证') ||
            html.contains('/cas/sec/initByType'));
  }

  String? _alertTitle(String html) {
    final match = RegExp(r'title="([^"]+)"').firstMatch(html);
    return match?.group(1);
  }

  String? _extractInput(String html, String name) {
    final pattern = RegExp(
      'name="$name"[^>]*value="([^"]*)"|value="([^"]*)"[^>]*name="$name"',
    );
    final match = pattern.firstMatch(html);
    return match?.group(1) ?? match?.group(2);
  }

  List<AccountChoice>? _extractAccounts(String html) {
    if (!html.contains('account-wrap')) return null;
    final names = RegExp(
      r'<div class="name">\s*([^<]+)\s*</div>',
    ).allMatches(html).map((m) => m.group(1)!.trim()).toList();
    final labels = RegExp(
      r'<el-radio[^>]*label="([^"]+)"',
    ).allMatches(html).map((m) => m.group(1)!).toList();
    if (names.isEmpty || names.length != labels.length) return null;
    return [
      for (var i = 0; i < names.length; i++)
        AccountChoice(name: names[i], label: labels[i]),
    ];
  }

  Map<String, dynamic> _jwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return {};
    var payload = parts[1];
    switch (payload.length % 4) {
      case 2:
        payload += '==';
      case 3:
        payload += '=';
    }
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (decoded is Map<String, dynamic>) return decoded;
    } on Object {
      return {};
    }
    return {};
  }

  String _fpVisitorId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _tail(String studentId) {
    if (studentId.length <= 4) return '****';
    return studentId.substring(studentId.length - 4);
  }
}

class _PendingCas {
  _PendingCas({
    required this.studentId,
    required this.encryptedPassword,
    required this.execution,
    required this.postUrl,
    required this.fpVisitorId,
  });

  final String studentId;
  final String encryptedPassword;
  final String execution;
  final String postUrl;
  final String fpVisitorId;
  String mfaState = '';
  bool mfaRequired = false;
  bool captchaRequired = false;
  bool safetyVerify = false;
  String? gid;
  String? maskedPhone;
  int failCount = 0;
  String? safetyHtml;
  String? safetyPostUrl;
  String? accountHtml;
  List<AccountChoice>? accountChoices;
}

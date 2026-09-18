import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/core_providers.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

class AuthState extends Equatable {
  const AuthState({
    required this.initialized,
    required this.user,
    this.busy = false,
    this.errorMessage,
    this.captchaImage,
    this.maskedPhone,
    this.awaitingMfa = false,
    this.awaitingCaptcha = false,
    this.awaitingAccountChoice = false,
    this.accountChoices = const [],
  });

  const AuthState.loading()
    : initialized = false,
      user = AuthUser.guest,
      busy = false,
      errorMessage = null,
      captchaImage = null,
      maskedPhone = null,
      awaitingMfa = false,
      awaitingCaptcha = false,
      awaitingAccountChoice = false,
      accountChoices = const [];

  final bool initialized;
  final AuthUser user;
  final bool busy;
  final String? errorMessage;
  final Uint8List? captchaImage;
  final String? maskedPhone;
  final bool awaitingMfa;
  final bool awaitingCaptcha;
  final bool awaitingAccountChoice;
  final List<AccountChoice> accountChoices;

  bool get isLoggedIn => !user.isGuest;

  AuthState copyWith({
    bool? initialized,
    AuthUser? user,
    bool? busy,
    String? errorMessage,
    Uint8List? captchaImage,
    String? maskedPhone,
    bool? awaitingMfa,
    bool? awaitingCaptcha,
    bool? awaitingAccountChoice,
    List<AccountChoice>? accountChoices,
    bool clearError = false,
    bool clearCaptcha = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      user: user ?? this.user,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      captchaImage: clearCaptcha ? null : (captchaImage ?? this.captchaImage),
      maskedPhone: maskedPhone ?? this.maskedPhone,
      awaitingMfa: awaitingMfa ?? this.awaitingMfa,
      awaitingCaptcha: awaitingCaptcha ?? this.awaitingCaptcha,
      awaitingAccountChoice:
          awaitingAccountChoice ?? this.awaitingAccountChoice,
      accountChoices: accountChoices ?? this.accountChoices,
    );
  }

  @override
  List<Object?> get props => [
    initialized,
    user,
    busy,
    errorMessage,
    captchaImage,
    maskedPhone,
    awaitingMfa,
    awaitingCaptcha,
    awaitingAccountChoice,
    accountChoices,
  ];
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    unawaited(restore());
    return const AuthState.loading();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> restore() async {
    if (kIsWeb) {
      await Future<void>.delayed(Duration.zero);
      if (ref.mounted)
        state = const AuthState(initialized: true, user: AuthUser.guest);
      return;
    }
    try {
      final user = await _repo.restoreSession().timeout(
        const Duration(seconds: 4),
      );
      if (!ref.mounted) return;
      state = AuthState(initialized: true, user: user ?? AuthUser.guest);
    } on Object {
      if (!ref.mounted) return;
      state = const AuthState(initialized: true, user: AuthUser.guest);
    }
  }

  Future<bool> login({
    required String studentId,
    required String password,
    String captcha = '',
    String? mfaCode,
    String? accountLabel,
    bool demo = false,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _repo.login(
        studentId: studentId,
        password: password,
        captcha: captcha,
        mfaCode: mfaCode,
        accountLabel: accountLabel,
        demo: demo,
      );
      state = AuthState(initialized: true, user: user);
      return true;
    } on CaptchaRequiredException catch (error) {
      state = state.copyWith(
        busy: false,
        initialized: true,
        captchaImage: error.image,
        awaitingCaptcha: true,
        errorMessage: error.message,
      );
      return false;
    } on MfaRequiredException catch (error) {
      state = state.copyWith(
        busy: false,
        initialized: true,
        awaitingMfa: true,
        maskedPhone: error.maskedPhone,
        errorMessage: error.message,
      );
      unawaited(sendMfaSms());
      return false;
    } on AccountChoiceRequiredException catch (error) {
      state = state.copyWith(
        busy: false,
        initialized: true,
        awaitingAccountChoice: true,
        accountChoices: error.choices,
        errorMessage: error.message,
      );
      return false;
    } on AuthException catch (error) {
      state = state.copyWith(
        busy: false,
        initialized: true,
        errorMessage: error.message,
      );
      return false;
    } on Object {
      state = state.copyWith(
        busy: false,
        initialized: true,
        errorMessage: '登录失败，请检查网络后重试',
      );
      return false;
    }
  }

  Future<void> refreshCaptcha() async {
    try {
      final image = await _repo.refreshCaptcha();
      state = state.copyWith(captchaImage: image, awaitingCaptcha: true);
    } on AuthException catch (error) {
      state = state.copyWith(errorMessage: error.message);
    }
  }

  Future<void> sendMfaSms() async {
    try {
      final phone = await _repo.sendMfaSms();
      state = state.copyWith(
        awaitingMfa: true,
        maskedPhone: phone,
        errorMessage: '验证码已发送至 $phone',
      );
    } on AuthException catch (error) {
      state = state.copyWith(errorMessage: error.message);
    }
  }

  Future<void> applyExternalLogin(AuthUser user) async {
    state = AuthState(initialized: true, user: user);
  }

  Future<void> logout() async {
    await _repo.logout();
    await ref.read(snapshotCacheProvider).clearAll();
    state = const AuthState(initialized: true, user: AuthUser.guest);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

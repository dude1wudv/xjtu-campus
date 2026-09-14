import 'dart:async';

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
  });

  const AuthState.loading()
    : initialized = false,
      user = AuthUser.guest,
      busy = true,
      errorMessage = null;

  final bool initialized;
  final AuthUser user;
  final bool busy;
  final String? errorMessage;

  bool get isLoggedIn => !user.isGuest;

  AuthState copyWith({
    bool? initialized,
    AuthUser? user,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      user: user ?? this.user,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [initialized, user, busy, errorMessage];
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    unawaited(restore());
    return const AuthState.loading();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> restore() async {
    try {
      final user = await _repo.restoreSession();
      state = AuthState(
        initialized: true,
        user: user ?? AuthUser.guest,
      );
    } on Object {
      state = const AuthState(initialized: true, user: AuthUser.guest);
    }
  }

  Future<bool> login({
    required String studentId,
    required String password,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final user = await _repo.login(
        studentId: studentId,
        password: password,
      );
      state = AuthState(initialized: true, user: user);
      return true;
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
        errorMessage: '登录失败，请稍后重试',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AuthState(initialized: true, user: AuthUser.guest);
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

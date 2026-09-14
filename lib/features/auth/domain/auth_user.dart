import 'package:equatable/equatable.dart';

class AuthUser extends Equatable {
  const AuthUser({
    required this.studentId,
    required this.displayName,
    required this.sessionToken,
    this.college,
  });

  final String studentId;
  final String displayName;
  final String sessionToken;
  final String? college;

  bool get isGuest => studentId.isEmpty;

  static const guest = AuthUser(
    studentId: '',
    displayName: '未登录',
    sessionToken: '',
  );

  @override
  List<Object?> get props => [studentId, displayName, sessionToken, college];
}

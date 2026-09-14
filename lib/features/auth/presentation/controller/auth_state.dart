import 'package:equatable/equatable.dart';

import '../../data/models/auth_session.dart';

enum AuthStatus {
  /// Startup: we have not yet read persisted tokens.
  unknown,

  /// No valid session — show the Login flow.
  unauthenticated,

  /// Signed in with a live session.
  authenticated,

  /// A refresh failed with `session_expired` — show the Session Expired screen
  /// (distinct from a clean logout so the UI can prompt re-auth in context).
  sessionExpired,
}

/// App-wide authentication state. The router redirects off [status].
class AuthState extends Equatable {
  const AuthState({required this.status, this.session});

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  final AuthStatus status;
  final AuthSession? session;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({AuthStatus? status, AuthSession? session}) => AuthState(
        status: status ?? this.status,
        session: session ?? this.session,
      );

  @override
  List<Object?> get props => [status, session];
}

/// The error codes the Connect protocol returns in `{"code": ...}`.
///
/// Only the ones this app reacts to differently are named; anything else
/// becomes [ApiErrorCode.unknown] and is shown as a generic failure.
enum ApiErrorCode {
  invalidArgument,
  notFound,
  alreadyExists,
  unauthenticated,
  permissionDenied,
  failedPrecondition,
  resourceExhausted,
  unavailable,
  unknown;

  static ApiErrorCode parse(String? raw) => switch (raw) {
    'invalid_argument' => ApiErrorCode.invalidArgument,
    'not_found' => ApiErrorCode.notFound,
    'already_exists' => ApiErrorCode.alreadyExists,
    'unauthenticated' => ApiErrorCode.unauthenticated,
    'permission_denied' => ApiErrorCode.permissionDenied,
    'failed_precondition' => ApiErrorCode.failedPrecondition,
    'resource_exhausted' => ApiErrorCode.resourceExhausted,
    'unavailable' => ApiErrorCode.unavailable,
    _ => ApiErrorCode.unknown,
  };
}

/// A failed API call. [message] comes from the server and is already written
/// for the user, so screens can show it directly.
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  /// The network never reached the API — a different problem from any error
  /// the API itself reports, and the only one worth suggesting a retry for.
  const ApiException.offline()
    : code = ApiErrorCode.unavailable,
      message = 'Sem conexão com o servidor. Verifique a rede e tente de novo.';

  final ApiErrorCode code;
  final String message;

  /// True when the session is missing or expired and the user must sign in
  /// again, which the app handles by returning to the login screen.
  bool get isSessionExpired => code == ApiErrorCode.unauthenticated;

  @override
  String toString() => 'ApiException(${code.name}): $message';
}

enum CallPreflightCode {
  peerBlocked,
  transportUnavailable,
  noLocalRoute,
  identityUnavailable,
  signalingUnavailable,
  activeCall,
}

final class CallPreflightException implements Exception {
  final CallPreflightCode code;
  final String userMessage;

  const CallPreflightException(this.code, this.userMessage);

  @override
  String toString() => userMessage;
}

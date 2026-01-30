/// NNTP-specific exceptions for error handling.
library;

/// Base exception for all NNTP errors.
class NNTPException implements Exception {
  final String message;
  final int? responseCode;

  const NNTPException(this.message, [this.responseCode]);

  @override
  String toString() {
    if (responseCode != null) {
      return 'NNTPException [$responseCode]: $message';
    }
    return 'NNTPException: $message';
  }
}

/// Connection-related errors (socket, TLS, timeout).
class NNTPConnectionException extends NNTPException {
  const NNTPConnectionException(super.message);
}

/// Authentication failed (480, 481, 482).
class NNTPAuthException extends NNTPException {
  const NNTPAuthException(super.message, [super.responseCode]);
}

/// Newsgroup not found (411).
class NNTPNoSuchGroupException extends NNTPException {
  final String groupName;

  const NNTPNoSuchGroupException(this.groupName)
      : super('No such newsgroup: $groupName', 411);
}

/// No newsgroup selected (412).
class NNTPNoGroupSelectedException extends NNTPException {
  const NNTPNoGroupSelectedException()
      : super('No newsgroup has been selected', 412);
}

/// Article not found (420, 423, 430).
class NNTPArticleNotFoundException extends NNTPException {
  final String? messageId;
  final int? articleNumber;

  const NNTPArticleNotFoundException.byMessageId(String this.messageId)
      : articleNumber = null,
        super('No article with message-id: $messageId', 430);

  const NNTPArticleNotFoundException.byNumber(int this.articleNumber)
      : messageId = null,
        super('No article with number: $articleNumber', 423);

  const NNTPArticleNotFoundException.invalidCurrent()
      : messageId = null,
        articleNumber = null,
        super('Current article number is invalid', 420);
}

/// Posting not allowed or failed (440, 441).
class NNTPPostingException extends NNTPException {
  const NNTPPostingException.notAllowed()
      : super('Posting not permitted', 440);

  const NNTPPostingException.failed(String reason)
      : super('Posting failed: $reason', 441);
}

/// Permission denied (502).
class NNTPPermissionDeniedException extends NNTPException {
  const NNTPPermissionDeniedException([String? message])
      : super(message ?? 'Permission denied', 502);
}

/// Service temporarily unavailable (400).
class NNTPServiceUnavailableException extends NNTPException {
  const NNTPServiceUnavailableException([String? message])
      : super(message ?? 'Service temporarily unavailable', 400);
}

/// Protocol error (unexpected response).
class NNTPProtocolException extends NNTPException {
  const NNTPProtocolException(super.message);
}

/// Command timeout.
class NNTPTimeoutException extends NNTPException {
  const NNTPTimeoutException([String? command])
      : super(command != null
            ? 'Timeout waiting for response to: $command'
            : 'Operation timed out');
}

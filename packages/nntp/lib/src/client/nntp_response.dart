/// NNTP response parsing.
library;

import '../exceptions.dart';

/// Represents an NNTP server response.
class NNTPResponse {
  /// Three-digit response code.
  final int code;

  /// Response message (first line after code).
  final String message;

  /// Multi-line response data (for responses like LIST, ARTICLE, etc.).
  final List<String>? data;

  const NNTPResponse(this.code, this.message, [this.data]);

  /// Whether the response indicates success (2xx).
  bool get isSuccess => code >= 200 && code < 300;

  /// Whether the response indicates error (4xx, 5xx).
  bool get isError => code >= 400;

  /// Whether this response has multi-line data.
  bool get hasData => data != null && data!.isNotEmpty;

  /// Response code categories.
  bool get isInformational => code >= 100 && code < 200;
  bool get isCommandOk => code >= 200 && code < 300;
  bool get isCommandOkSoFar => code >= 300 && code < 400;
  bool get isCommandFailed => code >= 400 && code < 500;
  bool get isCommandNotSupported => code >= 500 && code < 600;

  /// Specific response codes.
  static const int serviceAvailablePosting = 200;
  static const int serviceAvailableNoPosting = 201;
  static const int slaveStatusNoted = 202;
  static const int closingConnection = 205;
  static const int groupSelected = 211;
  static const int infoFollows = 215;
  static const int articleFollows = 220;
  static const int headFollows = 221;
  static const int bodyFollows = 222;
  static const int statOk = 223;
  static const int overviewFollows = 224;
  static const int newGroupsFollow = 231;
  static const int newArticlesFollow = 230;
  static const int articlePosted = 240;
  static const int authAccepted = 281;
  static const int sendArticle = 340;
  static const int continueWithAuth = 381;
  static const int serviceUnavailable = 400;
  static const int noSuchGroup = 411;
  static const int noGroupSelected = 412;
  static const int currentArticleInvalid = 420;
  static const int nextOrPrevNotInGroup = 421;
  static const int noArticleInRange = 423;
  static const int noArticleWithMsgId = 430;
  static const int postingNotAllowed = 440;
  static const int postingFailed = 441;
  static const int authRequired = 480;
  static const int authRejected = 481;
  static const int authError = 482;
  static const int commandNotRecognized = 500;
  static const int syntaxError = 501;
  static const int permissionDenied = 502;
  static const int featureNotSupported = 503;

  /// Parses the first line of an NNTP response.
  ///
  /// Format: "code message text"
  /// Example: "211 1234 3000 3999 comp.lang.dart"
  static NNTPResponse parseStatusLine(String line) {
    line = line.trim();
    if (line.length < 3) {
      throw const NNTPProtocolException('Invalid response: too short');
    }

    final code = int.tryParse(line.substring(0, 3));
    if (code == null) {
      throw NNTPProtocolException('Invalid response code: ${line.substring(0, 3)}');
    }

    final message = line.length > 4 ? line.substring(4) : '';
    return NNTPResponse(code, message);
  }

  /// Creates a response with multi-line data.
  NNTPResponse withData(List<String> data) => NNTPResponse(code, message, data);

  /// Throws an appropriate exception if this is an error response.
  void throwIfError() {
    switch (code) {
      case serviceUnavailable:
        throw NNTPServiceUnavailableException(message);
      case noSuchGroup:
        throw NNTPNoSuchGroupException(message);
      case noGroupSelected:
        throw const NNTPNoGroupSelectedException();
      case currentArticleInvalid:
        throw const NNTPArticleNotFoundException.invalidCurrent();
      case noArticleInRange:
        // Extract article number from message if possible
        final match = RegExp(r'\d+').firstMatch(message);
        if (match != null) {
          throw NNTPArticleNotFoundException.byNumber(int.parse(match.group(0)!));
        }
        throw NNTPException(message, code);
      case noArticleWithMsgId:
        throw NNTPArticleNotFoundException.byMessageId(message);
      case postingNotAllowed:
        throw const NNTPPostingException.notAllowed();
      case postingFailed:
        throw NNTPPostingException.failed(message);
      case authRequired:
      case authRejected:
      case authError:
        throw NNTPAuthException(message, code);
      case permissionDenied:
        throw NNTPPermissionDeniedException(message);
      default:
        if (isError) {
          throw NNTPException(message, code);
        }
    }
  }

  @override
  String toString() => 'NNTPResponse($code: $message)';
}

/// Codes that indicate a multi-line response follows.
const multilineResponseCodes = {
  NNTPResponse.infoFollows,        // 215 - LIST
  NNTPResponse.articleFollows,     // 220 - ARTICLE
  NNTPResponse.headFollows,        // 221 - HEAD
  NNTPResponse.bodyFollows,        // 222 - BODY
  NNTPResponse.overviewFollows,    // 224 - OVER/XOVER
  NNTPResponse.newGroupsFollow,    // 231 - NEWGROUPS
  NNTPResponse.newArticlesFollow,  // 230 - NEWNEWS
  100,                             // 100 - HELP
  101,                             // 101 - CAPABILITIES
  211,                             // 211 - GROUP (when followed by LISTGROUP)
};

/// Whether the given response code expects multi-line data.
bool expectsMultilineResponse(int code) => multilineResponseCodes.contains(code);

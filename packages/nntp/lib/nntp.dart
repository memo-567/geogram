/// NNTP (Network News Transfer Protocol) client library for Dart.
///
/// A pure Dart implementation following RFC 3977 for reading and posting
/// to Usenet newsgroups.
///
/// ## Usage
///
/// ```dart
/// import 'package:nntp/nntp.dart';
///
/// void main() async {
///   final client = NNTPClient(host: 'news.example.com');
///
///   // Connect to server
///   await client.connect();
///
///   // Authenticate if required
///   await client.authenticate('username', 'password');
///
///   // List newsgroups
///   final groups = await client.listGroups();
///
///   // Select a group
///   final group = await client.selectGroup('comp.lang.dart');
///
///   // Fetch overview data
///   final overview = await client.fetchOverview(range: Range(1, 100));
///
///   // Fetch a specific article
///   final article = await client.fetchArticle(12345);
///
///   // Disconnect
///   await client.disconnect();
/// }
/// ```
library nntp;

// Core client
export 'src/client/nntp_client.dart' show NNTPClient;
export 'src/client/nntp_connection.dart' show NNTPConnection;
export 'src/client/nntp_response.dart' show NNTPResponse;

// Models
export 'src/models/article.dart' show NNTPArticle;
export 'src/models/newsgroup.dart' show Newsgroup;
export 'src/models/overview.dart' show OverviewEntry;
export 'src/models/range.dart' show Range;

// Exceptions
export 'src/exceptions.dart';

// Command utilities
export 'src/commands/article.dart'
    show
        ArticleRetrievalMode,
        extractAuthorEmail,
        extractAuthorName,
        parseBody,
        parseHeaders;
export 'src/commands/auth.dart' show AuthMethod, AuthResponseCode;
export 'src/commands/capability.dart' show NNTPCapability;
export 'src/commands/group.dart' show GroupResponse;
export 'src/commands/list.dart'
    show ActiveEntry, ListCommand, parseNewsgroupDescriptions, standardOverviewFormat;
export 'src/commands/misc.dart' show NNTPDateFormat, parseNNTPDate;
export 'src/commands/over.dart' show OverviewField, normalizeRange, splitRange;
export 'src/commands/post.dart'
    show createAttribution, createFollowup, createReply, quoteText, validateArticle;

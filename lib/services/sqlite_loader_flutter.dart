import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart' as sqlite_libs;

/// SQLite loader for Flutter targets.
///
/// `sqlite3_flutter_libs` bundles native SQLite binaries for mobile and desktop,
/// so we simply open via sqlite3.
class SQLiteLoader {
  SQLiteLoader._();

  /// Open or create a database at [dbPath].
  static Database openDatabase(String dbPath) {
    // Ensure the bundled libs are registered (side effect of import).
    sqlite_libs; // ignore: unnecessary_statements
    return sqlite3.open(dbPath);
  }

  /// Open an in-memory database.
  static Database openInMemory() {
    sqlite_libs; // ignore: unnecessary_statements
    return sqlite3.openInMemory();
  }
}

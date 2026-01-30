import 'package:sqlite3/sqlite3.dart';
// ignore: unused_import
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// SQLite loader for Flutter targets.
///
/// `sqlite3_flutter_libs` bundles native SQLite binaries for mobile and desktop.
/// The import above ensures the native libraries are bundled with the app.
class SQLiteLoader {
  SQLiteLoader._();

  /// Open or create a database at [dbPath].
  static Database openDatabase(String dbPath) {
    return sqlite3.open(dbPath);
  }

  /// Open an in-memory database.
  static Database openInMemory() {
    return sqlite3.openInMemory();
  }
}

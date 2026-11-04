/// Local database configuration kept outside the SQLite implementation.
abstract final class DatabaseConfig {
  static const String name = 'locallink.db';
  static const int version = 34; // Bundle 209: sig3 in group copies
}

/// Local database configuration kept outside the SQLite implementation.
abstract final class DatabaseConfig {
  static const String name = 'locallink.db';
  static const int version = 32; // Bundle G5: group receipts per member
}

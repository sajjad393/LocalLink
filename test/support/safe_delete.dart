import 'dart:io';

/// Bundle 208 (A1): delete a test's temp folder. On Windows a file can
/// still be open (a picture loader, a log writer) for a moment after the
/// test, and deleting it then fails with errno 32. Try again once after
/// 50 ms, then leave it - it is only a temp folder. Synchronous on purpose
/// (safe inside testWidgets' fake time).
void safeDeleteDir(Directory dir) {
  for (var i = 0; i < 2; i++) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (i == 0) sleep(const Duration(milliseconds: 50));
    }
  }
}

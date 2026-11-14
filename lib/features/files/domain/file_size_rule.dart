import '../../../core/models/attachment.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 203 (5): files over 50 MB are not sent (no internet road can carry
/// them reliably). They are dropped when picked / forwarded, with a pop-up.
class FileSizeRule {
  FileSizeRule._();

  /// 50 MiB - the same limit as the phone's file sender
  /// (DirectFileTransferPolicy.MAX_DIRECT_FILE_SIZE) and group files.
  static const int maxBytes = 50 * 1024 * 1024;

  static bool tooBig(int size) => size > maxBytes;

  /// Splits picked files into the ones to keep and the too-big ones.
  static ({List<PickedFile> keep, List<PickedFile> dropped}) split(
      List<PickedFile> files) {
    final keep = <PickedFile>[];
    final dropped = <PickedFile>[];
    for (final f in files) {
      (tooBig(f.size) ? dropped : keep).add(f);
    }
    return (keep: keep, dropped: dropped);
  }

  static String title(int count) =>
      count == 1 ? L.t.fileTooBig : L.t.filesTooBig(count);

  static String body(int count, {bool forward = false, bool othersSent = true}) {
    if (forward) {
      final first = count == 1
          ? L.t.thisFileIsBiggerThan50
          : L.t.theseFilesAreBiggerThan50;
      return othersSent ? L.t.theOtherItemsWereForwarded(first) : first;
    }
    return count == 1
        ? L.t.thisFileIsBiggerThan502
        : L.t.theseFilesAreBiggerThan502;
  }

  /// "63 MB" style size for the pop-up list.
  static String sizeLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb >= 100 ? mb.round() : mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }
}

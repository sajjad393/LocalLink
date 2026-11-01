import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' show getDatabasesPath;

import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';

/// Phone storage numbers from Android (StatFs on the data partition).
class PhoneStorage {
  const PhoneStorage(this.total, this.free);
  final int total;
  final int free;
  bool get known => total > 0;
  int get usedPercent => total <= 0 ? 0 : ((total - free.clamp(0, total)) * 100 / total).round();
}

/// What a tap on removed media did.
enum RemovedTap { restored, openedSaved, gone }

/// Bundle 197b: "Free up space automatically", Settings › Storage, small
/// pictures, Gallery links and Save to phone. One instance per app run.
class MediaStorageService extends ChangeNotifier {
  MediaStorageService._();

  static final MediaStorageService instance = MediaStorageService._();

  static const MethodChannel _channel = MethodChannel('locallink/voice_notes');
  static const String keyAutoClean = 'storage_auto_clean';
  static const String keyLastClean = 'storage_last_clean';
  static const String keyBackfillDone = 'storage_thumb_backfill_done';
  static const Set<String> _sentStatuses = {'delivered', 'direct_delivered', 'read'};

  LocalStore? _store;
  FileTransferRepositoryContract? _files;
  bool Function() inCall = () => false;
  MediaBook book = MediaBook.instance;

  bool _autoClean = true;
  bool _busy = false;
  bool _started = false;
  DateTime? _lastRunAt;
  int _lastCount = 0;
  int _lastBytes = 0;
  int? _sdk;
  int _thumbFailures = 0;
  Future<void> _thumbChain = Future<void>.value();
  final Map<String, String> _thumbViews = <String, String>{};
  final Map<String, bool> _linkAlive = <String, bool>{};
  Timer? _startTimer;
  Timer? _backfillTimer;
  Timer? _afterDownload;

  bool get configured => _store != null;
  bool get autoClean => _autoClean;
  bool get busy => _busy;
  DateTime? get lastCleanAt => _lastRunAt;
  int get lastCleanCount => _lastCount;
  int get lastCleanBytes => _lastBytes;

  /// Called once LocalStore is open (main / home).
  Future<void> configure({
    required LocalStore store,
    required FileTransferRepositoryContract files,
    bool Function()? inCall,
  }) async {
    _store = store;
    _files = files;
    if (inCall != null) this.inCall = inCall;
    book.onReleaseLinks = (uris) => unawaited(_releaseLinks(uris));
    unawaited(sdkInt());
    book.onStaged = (id, path, type, name) {
      final kind = mediaKindOf(contentType: type, name: name, isImage: type.toLowerCase().startsWith('image/'));
      if (kind == MediaKind.photo || kind == MediaKind.video) {
        unawaited(ensureThumb(id, path, video: kind == MediaKind.video));
      }
    };
    try {
      _autoClean = (await store.readSetting(keyAutoClean) ?? '1') != '0';
      final last = await store.readSetting(keyLastClean);
      if (last != null && last.isNotEmpty) {
        final map = jsonDecode(last) as Map<String, dynamic>;
        _lastRunAt = DateTime.tryParse(map['at']?.toString() ?? '');
        _lastCount = (map['count'] as num?)?.toInt() ?? 0;
        _lastBytes = (map['bytes'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  /// Home screen is up: clean-up 60 s later, small pictures 2 min later.
  void start() {
    if (_started || _store == null) return;
    _started = true;
    _startTimer = Timer(MediaCleanPolicy.startDelay, () {
      unawaited(_startupHousekeeping());
    });
    _backfillTimer = Timer(const Duration(minutes: 2), () => unawaited(backfillThumbs()));
  }

  Future<void> _startupHousekeeping() async {
    await runAutoClean(trigger: 'start');
    await sweepPicks();
    await countOrphans();
    try {
      final kept = await _channel.invokeMethod<int>('link_count') ?? 0;
      final max = (await sdkInt()) >= 30 ? 512 : 128;
      AppLogger.info('GALLERY_LINKS', detail: 'kept=$kept max=$max');
    } catch (_) {}
  }

  void onResume() {
    if (!_started) return;
    unawaited(runAutoClean(trigger: 'resume'));
  }

  /// K1: a download bigger than 20 MB finished.
  void onDownloaded(int bytes) {
    if (!_started || bytes <= MediaCleanPolicy.bigDownloadBytes) return;
    _afterDownload?.cancel();
    _afterDownload = Timer(const Duration(seconds: 5), () => unawaited(runAutoClean(trigger: 'download')));
  }

  Future<void> setAutoClean(bool on) async {
    _autoClean = on;
    notifyListeners();
    AppLogger.info('STORAGE_AUTO_CLEAN', detail: on ? 'on' : 'off');
    try {
      await _store?.writeSetting(keyAutoClean, on ? '1' : '0');
    } catch (_) {}
  }

  Future<int> sdkInt() async {
    final cached = _sdk;
    if (cached != null) return cached;
    try {
      _sdk = await _channel.invokeMethod<int>('sdk_int') ?? 0;
    } catch (_) {
      _sdk = 0;
    }
    return _sdk!;
  }

  /// Q5: Save to phone only on Android 10+.
  bool get canSaveToPhone => (_sdk ?? 0) >= 29;

  Future<PhoneStorage> phoneStorage() async {
    final override = phoneForTest;
    if (override != null) return override();
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('storage_stats');
      final total = (map?['total'] as num?)?.toInt() ?? 0;
      final free = (map?['free'] as num?)?.toInt() ?? 0;
      return PhoneStorage(total, free);
    } catch (_) {
      return const PhoneStorage(0, 0);
    }
  }

  // ---------------------------------------------------------------- scan

  static String? diskPathOf(String rowPath) {
    if (rowPath.isEmpty) return null;
    try {
      if (File(rowPath).existsSync()) return rowPath;
      final enc = '$rowPath.enc';
      if (File(enc).existsSync()) return enc;
    } catch (_) {}
    return null;
  }

  /// Every media file of every chat, with what is on disk now.
  Future<List<MediaFile>> scan() async {
    final override = scanForTest;
    if (override != null) return override();
    final store = _store;
    if (store == null) return const [];
    final me = store.deviceId ?? '';
    final rows = await store.mediaFileRows();
    final out = <MediaFile>[];
    final seen = <String>{};
    for (final row in rows) {
      final id = row['file_id']?.toString() ?? '';
      if (id.isEmpty || !seen.add(id)) continue;
      final group = (row['is_group'] as num?)?.toInt() == 1;
      final sender = row['sender_id']?.toString() ?? '';
      final mine = me.isNotEmpty && sender == me;
      final chatId = group
          ? row['group_id']?.toString() ?? ''
          : (mine ? row['recipient_id']?.toString() ?? '' : sender);
      final sent = !mine ||
          (group
              ? ((row['server_seq'] as num?)?.toInt() ?? 0) > 0
              : _sentStatuses.contains(row['status']?.toString() ?? ''));
      final rowPath = row['local_path']?.toString() ?? '';
      final state = book.of(id);
      final removed = state?.isRemoved ?? false;
      final disk = removed ? null : diskPathOf(rowPath);
      var bytes = 0;
      if (disk != null) {
        try {
          bytes = File(disk).lengthSync();
        } catch (_) {}
      }
      final type = row['content_type']?.toString() ?? '';
      final name = row['original_name']?.toString() ?? '';
      out.add(MediaFile(
        fileId: id,
        messageId: row['message_id']?.toString() ?? '',
        chatId: chatId,
        isGroup: group,
        mine: mine,
        sent: sent,
        kind: mediaKindOf(contentType: type, name: name, isImage: (row['is_image'] as num?)?.toInt() == 1),
        name: name,
        contentType: type,
        rowPath: rowPath,
        diskPath: disk,
        bytes: bytes,
        messageAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0),
        openedAt: state?.openedAt,
        removed: removed,
        saved: state?.isSaved ?? false,
      ));
    }
    return out;
  }

  Future<StorageSummary> summary() async => StorageSummary.of(await scan());

  // -------------------------------------------------------------- remove

  Future<String> _picksDir() async {
    final root = await getDatabasesPath();
    return p.join(Directory(root).parent.path, 'files', 'locallink_picks');
  }

  Future<void> _deleteDisk(String path) async {
    final files = _files;
    String picks;
    try {
      picks = await _picksDir();
    } catch (_) {
      picks = '/nonexistent_picks';
    }
    for (final candidate in {path, if (!path.endsWith('.enc')) '$path.enc'}) {
      try {
        if (p.isWithin(picks, candidate)) {
          final f = File(candidate);
          if (await f.exists()) await f.delete();
        } else {
          await files?.deleteLocalFile(candidate);
        }
      } catch (_) {}
    }
  }

  /// K5 / U4: delete LinkUp's copy, keep the small picture, mark removed.
  /// Returns the bytes freed.
  Future<int> removeFiles(Iterable<MediaFile> files) async {
    var bytes = 0;
    for (final f in files) {
      if (!f.present) continue;
      if (f.rowPath.isNotEmpty) await _deleteDisk(f.rowPath);
      if (f.diskPath != null && f.diskPath != f.rowPath) await _deleteDisk(f.diskPath!);
      await book.markRemoved(f.fileId);
      bytes += f.bytes;
    }
    if (bytes > 0) notifyListeners();
    return bytes;
  }

  Future<int> deleteManual(List<MediaFile> files) async {
    final bytes = await removeFiles(files);
    AppLogger.info('MEDIA_DELETED_MANUAL', detail: 'count=${files.length} mb=${_mb(bytes)}');
    return bytes;
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  // ------------------------------------------------------------ clean-up

  /// One clean-up run. [test] = Admin "Test clean-up now" (Q4): files are
  /// treated as 11 days old and the phone as 80% full.
  Future<int> runAutoClean({required String trigger, bool test = false, DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final reason = MediaCleanPolicy.skipReason(
      switchOn: _autoClean,
      inCall: inCall(),
      busy: _busy,
      trigger: trigger,
      lastRun: _lastRunAt,
      now: clock,
    );
    if (reason != null || _store == null) {
      final why = reason ?? 'not_ready';
      AppLogger.info(test ? 'MEDIA_CLEAN_TEST' : 'MEDIA_CLEAN_SKIPPED',
          detail: test ? 'removed=0 reason=$why' : 'reason=$why trigger=$trigger');
      return 0;
    }
    _busy = true;
    final started = DateTime.now();
    try {
      final phone = await phoneStorage();
      final total = phone.total;
      final free = test ? (total * 0.2).floor() : phone.free;
      final files = await scan();
      final linkup = files.fold<int>(0, (s, f) => s + (f.present ? f.bytes : 0));
      AppLogger.info('STORAGE_CHECK',
          detail: 'used=${phone.usedPercent}% free_mb=${(phone.free / (1024 * 1024)).round()} '
              'linkup_mb=${(linkup / (1024 * 1024)).round()}${test ? ' test=y' : ''}');
      if (!phone.known || !MediaCleanPolicy.overLimit(total, free)) {
        if (test) {
          AppLogger.info('MEDIA_CLEAN_TEST', detail: 'removed=0 reason=no_storage_info');
        } else {
          AppLogger.info('MEDIA_CLEAN_SKIPPED', detail: 'reason=under70 trigger=$trigger');
        }
        _lastRunAt = clock;
        await _saveLast(clock, _lastCount, _lastBytes);
        return 0;
      }
      final result = MediaCleanPolicy.pick(
        files,
        now: test ? clock.add(const Duration(days: 11)) : clock,
        totalBytes: total,
        freeBytes: free,
        // Test: "11 days old" = every file counts as older than 10 days.
        age: test ? const Duration(days: 10) : MediaCleanPolicy.minAge,
      );
      final bytes = await removeFiles(result.picked);
      int count(MediaKind k) => result.picked.where((f) => f.kind == k).length;
      final ms = DateTime.now().difference(started).inMilliseconds;
      final detail = 'count=${result.picked.length} mb=${_mb(bytes)} photos=${count(MediaKind.photo)} '
          'videos=${count(MediaKind.video)} docs=${count(MediaKind.document)} '
          'skipped_recent=${result.skippedRecent} skipped_unsent=${result.skippedUnsent} ms=$ms';
      AppLogger.info(test ? 'MEDIA_CLEAN_TEST' : 'MEDIA_CLEANED', detail: detail);
      _lastRunAt = clock;
      if (result.picked.isNotEmpty) {
        _lastCount = result.picked.length;
        _lastBytes = bytes;
      }
      await _saveLast(clock, _lastCount, _lastBytes);
      notifyListeners();
      return result.picked.length;
    } catch (error) {
      AppLogger.warning('MEDIA_CLEAN_SKIPPED', detail: 'reason=error trigger=$trigger error=$error');
      return 0;
    } finally {
      _busy = false;
    }
  }

  Future<void> _saveLast(DateTime at, int count, int bytes) async {
    try {
      await _store?.writeSetting(
          keyLastClean, jsonEncode({'at': at.toIso8601String(), 'count': count, 'bytes': bytes}));
    } catch (_) {}
  }

  // ------------------------------------------------------ small pictures

  Future<String> _thumbTarget(String fileId) async {
    final root = await getDatabasesPath();
    final safe = fileId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return p.join(root, 'attachments', 'thumbs', '$safe.jpg');
  }

  /// T1: one small picture at a time, from a plain (not encrypted) file.
  Future<bool> ensureThumb(String fileId, String plainPath, {required bool video}) {
    final done = Completer<bool>();
    _thumbChain = _thumbChain.then((_) async {
      done.complete(await _makeThumb(fileId, plainPath, video: video));
    }).catchError((Object _) {
      if (!done.isCompleted) done.complete(false);
    });
    return done.future;
  }

  Future<bool> _makeThumb(String fileId, String plainPath, {required bool video}) async {
    if (fileId.isEmpty || plainPath.isEmpty) return false;
    if (book.of(fileId)?.hasThumb ?? false) return true;
    if (inCall()) return false;
    try {
      final out = await _thumbTarget(fileId);
      final info = await _channel.invokeMapMethod<String, Object?>('make_thumb', {
        'in': plainPath,
        'out': out,
        'video': video,
        'max_px': 320,
      });
      final enc = await _files!.protectLegacyLocalFile(out);
      await book.setThumb(fileId, enc, mediaMs: (info?['duration_ms'] as num?)?.toInt() ?? 0);
      return true;
    } catch (error) {
      if (_thumbFailures++ < 5) {
        AppLogger.warning('THUMB_FAILED', detail: 'file=${_short(fileId)} error=$error');
      }
      return false;
    }
  }

  static String _short(String id) => id.length > 8 ? id.substring(id.length - 8) : id;

  /// A plain copy of the small picture for display (kept for this run).
  Future<String?> thumbView(String fileId) async {
    final state = book.of(fileId);
    if (state == null || !state.hasThumb) return null;
    final cached = _thumbViews[fileId];
    if (cached != null && File(cached).existsSync()) return cached;
    try {
      final view = await _files!.materializeForDisplay(state.thumbPath!, extension: '.jpg');
      if (_thumbViews.length >= 80) _thumbViews.remove(_thumbViews.keys.first);
      _thumbViews[fileId] = view;
      return view;
    } catch (_) {
      return null;
    }
  }

  /// T2: old photos / videos without a small picture - once, slowly.
  Future<void> backfillThumbs() async {
    final store = _store;
    final files = _files;
    if (store == null || files == null) return;
    try {
      if (await store.readSetting(keyBackfillDone) == '1') return;
    } catch (_) {}
    final started = DateTime.now();
    var made = 0, failed = 0;
    final todo = (await scan())
        .where((f) => f.present && (f.kind == MediaKind.photo || f.kind == MediaKind.video))
        .where((f) => !(book.of(f.fileId)?.hasThumb ?? false))
        .toList()
      ..sort((a, b) => b.messageAt.compareTo(a.messageAt));
    var stopped = false;
    for (final f in todo) {
      if (inCall() || WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
        stopped = true;
        break;
      }
      String? view;
      try {
        final disk = f.diskPath!;
        final protected = await files.isProtectedLocalFile(disk);
        final ext = f.name.contains('.') ? '.${f.name.split('.').last}' : (f.kind == MediaKind.video ? '.mp4' : '.jpg');
        final plain = protected ? (view = await files.materializeForDisplay(disk, extension: ext)) : disk;
        if (await _makeThumb(f.fileId, plain, video: f.kind == MediaKind.video)) {
          made++;
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      } finally {
        if (view != null) {
          try {
            await File(view).delete();
          } catch (_) {}
        }
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    AppLogger.info('THUMB_BACKFILL',
        detail: 'made=$made failed=$failed left=${stopped ? todo.length - made - failed : 0} '
            'ms=${DateTime.now().difference(started).inMilliseconds}');
    if (!stopped) {
      try {
        await store.writeSetting(keyBackfillDone, '1');
      } catch (_) {}
    }
  }

  // ------------------------------------------------- Gallery / save copy

  Future<void> _releaseLinks(List<String> uris) async {
    try {
      await _channel.invokeMethod('release_uris', {'uris': uris});
    } catch (_) {}
  }

  /// Cached for this run: the sender's Gallery copy still opens.
  bool? linkAliveCached(String fileId) => _linkAlive[fileId];

  Future<bool> linkAlive(String fileId) async {
    final uri = book.of(fileId)?.sourceUri ?? '';
    if (uri.isEmpty) return false;
    bool alive;
    try {
      alive = await _channel.invokeMethod<bool>('uri_alive', {'uri': uri}) ?? false;
    } catch (_) {
      alive = false;
    }
    if (!alive && _linkAlive[fileId] != false) {
      AppLogger.info('GALLERY_LINK_DEAD', detail: 'file=${_short(fileId)}');
    }
    _linkAlive[fileId] = alive;
    return alive;
  }

  /// V4 / V5: tap on removed media.
  Future<RemovedTap> tapRemoved(Attachment attachment, {required bool mine}) async {
    final id = attachment.id;
    final state = book.of(id);
    final kind = mediaKindOf(contentType: attachment.contentType, name: attachment.originalName, isImage: attachment.isImage);
    if (mine && (state?.hasSource ?? false) && (attachment.localPath ?? '').isNotEmpty) {
      if (await linkAlive(id)) {
        try {
          await _channel.invokeMethod('restore_from_uri', {'uri': state!.sourceUri, 'out': attachment.localPath});
          await book.clearRemoved(id);
          await book.markOpened(id);
          AppLogger.info('MEDIA_RESTORED_FROM_GALLERY', detail: 'kind=${kind.name}');
          notifyListeners();
          return RemovedTap.restored;
        } catch (error) {
          AppLogger.warning('GALLERY_LINK_DEAD', detail: 'file=${_short(id)} error=$error');
          _linkAlive[id] = false;
        }
      }
      return RemovedTap.gone;
    }
    if (!mine && (state?.isSaved ?? false)) {
      try {
        final alive = await _channel.invokeMethod<bool>('saved_alive', {'uri': state!.savedUri}) ?? false;
        if (alive) {
          final opened = await _channel.invokeMethod<bool>(
                  'open_uri', {'uri': state.savedUri, 'mime': attachment.contentType}) ??
              false;
          if (opened) return RemovedTap.openedSaved;
        } else {
          await book.clearSaved(id);
        }
      } catch (_) {}
    }
    return RemovedTap.gone;
  }

  /// P2: copy a received file to Gallery › LinkUp / Download › LinkUp.
  /// Returns the snackbar text.
  Future<String> saveToPhone(Attachment attachment) async {
    final files = _files;
    final kind = mediaKindOf(contentType: attachment.contentType, name: attachment.originalName, isImage: attachment.isImage);
    String? view;
    try {
      final disk = diskPathOf(attachment.localPath ?? '');
      if (files == null || disk == null) throw StateError('no_file');
      final ext = attachment.originalName.contains('.') ? '.${attachment.originalName.split('.').last}' : '.bin';
      final plain = await files.isProtectedLocalFile(disk)
          ? (view = await files.materializeForDisplay(disk, extension: ext))
          : disk;
      final mime = attachment.contentType.isEmpty ? 'application/octet-stream' : attachment.contentType;
      final uri = await _channel.invokeMethod<String>(
          'save_to_phone', {'path': plain, 'name': attachment.originalName, 'mime': mime});
      if (uri == null || uri.isEmpty) throw StateError('no_uri');
      await book.setSaved(attachment.id, uri);
      await book.markOpened(attachment.id);
      AppLogger.info('MEDIA_SAVED_TO_PHONE',
          detail: 'type=${kind.name} kb=${(File(plain).lengthSync() / 1024).round()}');
      return kind == MediaKind.document ? 'Saved to Download › LinkUp' : 'Saved to Gallery › LinkUp';
    } catch (error) {
      AppLogger.warning('MEDIA_SAVE_FAILED', detail: 'type=${kind.name} error=$error');
      return 'Could not save. Free some space and try again.';
    } finally {
      if (view != null) {
        try {
          await File(view).delete();
        } catch (_) {}
      }
    }
  }

  // ------------------------------------------------------ housekeeping

  /// G5 / L2: picker copies older than 24 h that no message uses.
  Future<void> sweepPicks({DateTime? now}) async {
    final store = _store;
    if (store == null) return;
    try {
      final dir = Directory(await _picksDir());
      if (!await dir.exists()) return;
      final used = await store.referencedLocalPaths();
      final cutoff = (now ?? DateTime.now()).subtract(const Duration(hours: 24));
      var count = 0, bytes = 0;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        final path = entry.path;
        if (used.contains(path) || used.contains(path.replaceAll(RegExp(r'\.enc$'), ''))) continue;
        try {
          final stat = await entry.stat();
          if (!stat.modified.isBefore(cutoff)) continue;
          bytes += stat.size;
          await entry.delete();
          count++;
        } catch (_) {}
      }
      AppLogger.info('PICKS_SWEPT', detail: 'count=$count mb=${_mb(bytes)}');
    } catch (error) {
      AppLogger.warning('PICKS_SWEPT', detail: 'error=$error');
    }
  }

  /// L4: files in `attachments` that no row names - counted only.
  Future<void> countOrphans() async {
    final store = _store;
    if (store == null) return;
    try {
      final root = Directory(p.join(await getDatabasesPath(), 'attachments'));
      if (!await root.exists()) return;
      final used = <String>{};
      for (final path in await store.referencedLocalPaths()) {
        used
          ..add(path)
          ..add('$path.enc');
      }
      final ids = <String>{for (final s in book.all) s.fileId};
      var count = 0, bytes = 0;
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = p.basename(entry.path);
        if (used.contains(entry.path)) continue;
        if (name.startsWith('.') || name.contains('view') || name.endsWith('.part')) continue;
        final thumbOf = name.split('-thumb').first;
        if (name.contains('-thumb') && ids.contains(thumbOf)) continue;
        count++;
        try {
          bytes += await entry.length();
        } catch (_) {}
      }
      AppLogger.info('STORAGE_ORPHANS', detail: 'count=$count mb=${_mb(bytes)}');
    } catch (_) {}
  }

  /// Storage screen: a plain copy of a photo to show full screen.
  Future<String?> viewOf(MediaFile f) async {
    final files = _files;
    final disk = f.diskPath;
    if (files == null || disk == null) return null;
    if (!await files.isProtectedLocalFile(disk)) return disk;
    final ext = f.name.contains('.') ? '.${f.name.split('.').last}' : '.jpg';
    return files.materializeForDisplay(disk, extension: ext);
  }

  /// Drop a view copy made by [viewOf] (never the real file).
  void dropView(String path) {
    if (!p.basename(path).startsWith('.view-')) return;
    unawaited(_files?.deleteLocalFile(path));
  }

  @visibleForTesting
  Future<List<MediaFile>> Function()? scanForTest;
  @visibleForTesting
  Future<PhoneStorage> Function()? phoneForTest;

  @visibleForTesting
  void resetForTest() {
    scanForTest = null;
    phoneForTest = null;
    _store = null;
    _files = null;
    _started = false;
    _busy = false;
    _autoClean = true;
    _lastRunAt = null;
    _lastCount = 0;
    _lastBytes = 0;
    _sdk = null;
    _thumbViews.clear();
    _linkAlive.clear();
    _startTimer?.cancel();
    _backfillTimer?.cancel();
    _afterDownload?.cancel();
    inCall = () => false;
  }

  @visibleForTesting
  void setSdkForTest(int sdk) => _sdk = sdk;

  @visibleForTesting
  void configureForTest({LocalStore? store, FileTransferRepositoryContract? files}) {
    _store = store;
    _files = files;
  }
}

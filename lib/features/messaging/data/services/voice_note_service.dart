import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:locallink/core/models/attachment.dart';

/// Bundle 181: what the voice recorder needs from the phone (a fake in tests).
abstract class VoiceRecorderBackend {
  /// Starts a new part; returns its path.
  Future<String> startPart();

  /// Stops the current part; returns its path, or null when it was too short.
  Future<String?> stopPart();

  /// Stops and deletes the current part (if any).
  Future<void> cancelPart();

  /// Live mic level 0..32767 (0 when not recording).
  Future<int> amplitude();

  /// Joins [parts] into one file (the parts are deleted after a good join).
  Future<PickedFile> join(List<String> parts);

  /// Plays [path]; returns its length in ms.
  Future<int> play(String path);

  Future<void> stopPlayback();

  void deleteFile(String path);
}

class VoiceNoteService implements VoiceRecorderBackend {
  static const _channel = MethodChannel('locallink/voice_notes');

  Future<PickedFile> record() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('record_start');
    if (result == null) throw StateError('Voice recording could not start');
    final path = result['path']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Voice recording path is unavailable');
    return PickedFile(path: path, name: result['name']?.toString() ?? 'voice_note.m4a', contentType: 'audio/mp4', size: int.tryParse(result['size']?.toString() ?? '') ?? 0);
  }

  Future<PickedFile> stop() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('record_stop');
    if (result == null) throw StateError('Voice recording could not be saved');
    final path = result['path']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Voice recording path is unavailable');
    return PickedFile(path: path, name: result['name']?.toString() ?? 'voice_note.m4a', contentType: 'audio/mp4', size: int.tryParse(result['size']?.toString() ?? '') ?? 0);
  }

  Future<void> cancel() => _channel.invokeMethod('record_cancel');

  @override
  Future<String> startPart() async => (await record()).path;

  @override
  Future<String?> stopPart() async {
    try {
      return (await stop()).path;
    } on PlatformException catch (e) {
      if (e.code == 'TOO_SHORT' || e.code == 'NO_RECORDING') return null;
      rethrow;
    }
  }

  @override
  Future<void> cancelPart() async {
    try {
      await cancel();
    } catch (_) {}
  }

  @override
  Future<PickedFile> join(List<String> parts) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'join', {'paths': parts, 'delete_parts': true});
    if (result == null) throw StateError('Voice note could not be saved');
    final path = result['path']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Voice note could not be saved');
    return PickedFile(path: path, name: result['name']?.toString() ?? 'voice_note.m4a', contentType: 'audio/mp4', size: int.tryParse(result['size']?.toString() ?? '') ?? 0);
  }

  @override
  void deleteFile(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  /// Live mic amplitude (0..32767) while recording. 0 when idle or if the
  /// native side is mid-transition — the wave UI fades instead of erroring.
  @override
  Future<int> amplitude() async {
    try {
      return (await _channel.invokeMethod<int>('amplitude')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<int> play(String path) async => (await _channel.invokeMethod<int>('play', {'path': path})) ?? 0;
  Future<void> pause() => _channel.invokeMethod('pause');
  @override
  Future<void> stopPlayback() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}

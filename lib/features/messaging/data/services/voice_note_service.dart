import 'dart:async';
import 'package:flutter/services.dart';
import 'package:locallink/core/models/attachment.dart';

class VoiceNoteService {
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
  Future<int> play(String path) async => (await _channel.invokeMethod<int>('play', {'path': path})) ?? 0;
  Future<void> pause() => _channel.invokeMethod('pause');
  Future<void> stopPlayback() => _channel.invokeMethod('stop');
}

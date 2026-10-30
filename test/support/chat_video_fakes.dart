// Shared fakes for chat video tests (bundles 145/147).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/files/presentation/widgets/media_playback_coordinator.dart';

class FakeVideoController extends ChangeNotifier implements ChatVideoController {
  FakeVideoController(this.path, {this.duration = const Duration(seconds: 31)});

  final String path;
  final Duration duration;
  bool _init = false, _playing = false, _muted = false, closed = false;
  Duration _pos = Duration.zero;
  final List<Duration> seeks = <Duration>[];

  @override
  ChatVideoState get state => ChatVideoState(
        initialized: _init,
        playing: _playing,
        position: _pos,
        duration: _init ? duration : Duration.zero,
        aspectRatio: 16 / 9,
      );

  @override
  bool get muted => _muted;

  @override
  Future<void> initialize() async {
    _init = true;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    notifyListeners();
  }

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    _pos = position;
    notifyListeners();
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    notifyListeners();
  }

  @override
  Widget buildView() => const ColoredBox(key: Key('fake_view'), color: Colors.blue);

  @override
  Future<void> close() async => closed = true;
}

class FakePip implements PipPlatform {
  final calls = <String>[];
  final events$ = StreamController<Map<Object?, Object?>>.broadcast();

  @override
  Future<void> setReady(
      {required bool ready, required double aspect, required bool playing}) async {
    calls.add('ready=$ready playing=$playing aspect=${aspect.toStringAsFixed(2)}');
  }

  @override
  Stream<Map<Object?, Object?>> events() => events$.stream;
}

class Rig {
  final controllers = <FakeVideoController>[];
  final released = <String>[];
  int retained = 0;
  final coordinator = MediaPlaybackCoordinator();
  final pip = FakePip();
  late final hub = ChatVideoHub(pip: pip);

  ChatVideoPlayer player(String path, {bool uploading = false}) => ChatVideoPlayer(
        key: ValueKey(path),
        path: path,
        cacheKey: 'k-$path',
        sizeBytes: 6920601, // 6.6 MB
        uploading: uploading,
        coordinator: coordinator,
        hub: hub,
        onRetainFile: () => retained++,
        onReleaseFile: released.add,
        infoLoader: (p, k) async =>
            const VideoInfo(durationMs: 31000, width: 1280, height: 720),
        controllerFactory: (p) {
          final c = FakeVideoController(p);
          controllers.add(c);
          return c;
        },
      );
}

Widget host(List<Widget> children, {ChatVideoHub? hub}) => MaterialApp(
      home: Scaffold(body: ListView(children: children)),
      builder: hub == null
          ? null
          : (context, child) => ChatVideoShell(hub: hub, child: child!),
    );

Future<void> tapKey(WidgetTester t, String key, {int index = 0}) async {
  await t.tap(find.byKey(Key(key)).at(index));
  await t.pump();
  await t.pump();
}


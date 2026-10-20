import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/presentation/widgets/call_video_view.dart';

CallSession _session({
  bool videoEnabled = true,
  bool peerVideoActive = true,
  int? localTextureId,
  int? remoteTextureId,
  int remoteRotation = 90,
  int remoteWidth = 1280,
  int remoteHeight = 720,
}) {
  return CallSession(
    id: 'video-ui',
    peerId: 'peer-1',
    peerName: 'Peer',
    direction: CallDirection.outgoing,
    state: CallState.connected,
    startedAt: DateTime.now(),
    transportMode: CallTransportMode.auto,
    videoEnabled: videoEnabled,
    peerVideoActive: peerVideoActive,
    localVideoTextureId: localTextureId,
    remoteVideoTextureId: remoteTextureId,
    localVideoRotation: 90,
    remoteVideoRotation: remoteRotation,
    localVideoWidth: 1280,
    localVideoHeight: 720,
    remoteVideoWidth: remoteWidth,
    remoteVideoHeight: remoteHeight,
  );
}

Widget _wrap(Widget child, {Size size = const Size(400, 700)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: SizedBox(width: size.width, height: size.height, child: child)),
    ),
  );
}

void main() {
  testWidgets('remote video fills screen AND local PiP renders with flip icon', (tester) async {
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(localTextureId: 11, remoteTextureId: 22),
      onSelfPreviewTap: () {},
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Texture), findsNWidgets(2)); // remote full + local PiP
    expect(find.byIcon(Icons.cameraswitch_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_rounded), findsNothing);
  });

  testWidgets('tapping the PiP triggers the camera-flip callback', (tester) async {
    var flips = 0;
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(localTextureId: 11, remoteTextureId: 22),
      onSelfPreviewTap: () => flips++,
    )));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
    expect(flips, 1);
  });

  testWidgets('peer streaming expected but no texture yet -> connecting state', (tester) async {
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(localTextureId: 11, remoteTextureId: null),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Connecting video…'), findsOneWidget);
  });

  testWidgets('own camera starting without remote -> starting-camera state', (tester) async {
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(peerVideoActive: false, localTextureId: null),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Starting camera…'), findsOneWidget);
  });

  testWidgets('no video at all -> camera-off glyph', (tester) async {
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(videoEnabled: false, peerVideoActive: false),
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
  });

  testWidgets('dragging the PiP moves it away from the default corner', (tester) async {
    await tester.pumpWidget(_wrap(CallVideoView(
      session: _session(localTextureId: 11, remoteTextureId: 22),
      onSelfPreviewTap: () {},
    )));
    await tester.pump(const Duration(seconds: 1));
    final pipIcon = find.byIcon(Icons.cameraswitch_rounded);
    final pipGestures = find.descendant(
        of: find.byType(CallVideoView), matching: find.byType(GestureDetector));
    final before = tester.getTopLeft(pipIcon);
    // drag the PiP gesture surface directly (the icon itself is a passive
    // badge), far enough to cross pan slop and force a corner snap
    final g = await tester.startGesture(tester.getCenter(pipGestures.last));
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(-25, 30));
      await tester.pump();
    }
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    final after = tester.getTopLeft(pipIcon);
    expect(after, isNot(before));
    // moved substantially towards the left/bottom corner; exact corner snap
    // is animation-timing dependent and covered by the manual checklist
    expect(after.dx, lessThan(before.dx - 100));
  });
}

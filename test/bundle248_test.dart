import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/presentation/widgets/call_action_bar.dart';

import 'call_fix_146_test.dart' show FakeGateway, HistoryRepository;

// Bundle 248: the camera button is back in a connected nearby call.

class _Gw extends FakeGateway {
  int videos = 0;
  @override
  Future<void> toggleVideo() async => videos++;
}

CallSession _s({CallState state = CallState.connected, bool direct = true, bool video = false}) => CallSession(
      id: 'c1',
      peerId: 'p',
      peerName: 'Ali',
      direction: CallDirection.outgoing,
      state: state,
      startedAt: DateTime.now(),
      transportMode: CallTransportMode.auto,
      directMode: direct,
      videoEnabled: video,
    );

void main() {
  test('only a connected nearby call shows it', () {
    expect(showVideoButton248(_s()), isFalse); // Bundle 277: video button hidden
    expect(showVideoButton248(_s(state: CallState.connecting)), isFalse);
    expect(showVideoButton248(_s(state: CallState.ringing)), isFalse);
    expect(showVideoButton248(_s(direct: false)), isFalse);
  });

  testWidgets('tap = toggleVideo; icon follows the camera', (tester) async {
    final gw = _Gw();
    final bloc = CallBloc(service: gw, repository: HistoryRepository());
    addTearDown(bloc.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallActionBar(controller: bloc, session: _s()))));
    // Bundle 277: no camera button in any call state.
    expect(find.byKey(const Key('call_video_toggle_248')), findsNothing);
    expect(gw.videos, 0);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallActionBar(controller: bloc, session: _s(video: true)))));
    expect(find.byKey(const Key('call_video_toggle_248')), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CallActionBar(controller: bloc, session: _s(state: CallState.connecting)))));
    expect(find.byKey(const Key('call_video_toggle_248')), findsNothing);
  });
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/notifications/local_link_notification_platform.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/core/notifications/notification_id.dart';
import 'package:locallink/core/notifications/notification_media_text.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';

import 'support/phase5_fakes.dart';

Attachment _a(String name, String type, {bool image = false}) => Attachment(
    id: name, originalName: name, contentType: type, size: 1, sha256: 'x',
    isImage: image);

final _img = _a('p.jpg', 'image/jpeg', image: true);
final _vid = _a('v.mp4', 'video/mp4');
final _voice = _a('voice.m4a', 'audio/mp4');
final _pdf = _a('cv.pdf', 'application/pdf');

class _Messaging extends Fake implements MessagingRepositoryContract {}

class _Groups extends Fake implements GroupMessagingRepositoryContract {}

class _Gateway extends Fake implements CallGateway {}

class _Store extends FakeStore {
  final Set<String> blocked = <String>{};
  final Map<String, Device> devices = <String, Device>{};
  final List<String> markedRead = <String>[];

  @override
  Future<bool> isBlockedPeer(String peerId) async => blocked.contains(peerId);

  @override
  Future<Device?> deviceById(String deviceId) async => devices[deviceId];

  @override
  Future<Message?> messageById(String id) async => messages[id];

  @override
  Future<void> markMessageRead(String id) async => markedRead.add(id);

  @override
  Future<void> removeNotificationStateForMessage(String messageId) async {}

  @override
  Future<List<Message>> unreadMessagesForConversation(String otherId) async =>
      const <Message>[];
}

LocalLinkNotificationAction _open({
  required int notificationId,
  String conversationId = 'peer-1',
  String messageId = '',
  NotificationConversationType type = NotificationConversationType.direct,
}) =>
    LocalLinkNotificationAction(
      action: NotificationActionType.open,
      conversationType: type,
      notificationId: '$notificationId',
      messageId: messageId,
      conversationId: conversationId,
      senderId: messageId.isEmpty ? '' : conversationId,
      recipientId: messageId.isEmpty ? '' : 'self-device',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('item 4: notification text', () {
    test('text only', () {
      expect(notificationBodyFor(' Hi ', const []), 'Hi');
      expect(notificationBodyFor('', const []), 'New message');
    });

    test('one file of each kind', () {
      expect(notificationBodyFor('', [_img]), 'Image received');
      expect(notificationBodyFor('', [_vid]), 'Video received');
      expect(notificationBodyFor('', [_voice]), 'Voice message received');
      expect(notificationBodyFor('', [_pdf]), 'Document received');
    });

    test('kind from the file name when the type is generic', () {
      expect(
          notificationBodyFor(
              '', [_a('clip.MOV', 'application/octet-stream')]),
          'Video received');
      expect(notificationBodyFor('', [_a('a.opus', 'application/octet-stream')]),
          'Voice message received');
      expect(notificationBodyFor('', [_a('x.png', 'application/octet-stream')]),
          'Image received');
    });

    test('caption is added after the label', () {
      expect(notificationBodyFor('Look at this', [_img]),
          'Image received: Look at this');
      expect(notificationBodyFor('  party ', [_vid]), 'Video received: party');
    });

    test('several files', () {
      expect(notificationBodyFor('', [_img, _img, _img]), '3 images received');
      expect(notificationBodyFor('', [_vid, _vid]), '2 videos received');
      expect(notificationBodyFor('', [_voice, _voice]),
          '2 voice messages received');
      expect(notificationBodyFor('', [_pdf, _pdf]), '2 documents received');
      expect(notificationBodyFor('', [_img, _vid, _pdf]), '3 files received');
      expect(notificationBodyFor('trip', [_img, _img]),
          '2 images received: trip');
    });
  });

  group('item 5: tap opens the chat', () {
    const notifications = MethodChannel('locallink/notifications');
    const actionsChannel = 'locallink/notification_actions';
    late _Store store;
    late LocalLinkNotificationService service;

    setUp(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(notifications, (_) async => null);
      messenger.setMockMethodCallHandler(
          const MethodChannel(actionsChannel), (_) async => null);
      store = _Store()
        ..devices['peer-1'] = const Device(
            id: 'peer-1', name: 'Ali', platform: 'android',
            createdAt: '', lastSeenAt: '');
      service = LocalLinkNotificationService(
        store: store,
        messaging: _Messaging(),
        groups: _Groups(),
        calls: CallBloc(service: _Gateway(), repository: FakeCallRepository()),
      );
    });

    Future<List<LocalLinkNotificationAction>> run(
        LocalLinkNotificationAction action) async {
      final got = <LocalLinkNotificationAction>[];
      final sub = service.openRequests.listen(got.add);
      await service.handleActionForTest(action);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      return got;
    }

    test('bundle tap ("3 new messages") opens the conversation', () async {
      final got = await run(_open(
          notificationId: LocalLinkNotificationId.directSummary('peer-1')));
      expect(got.single.conversationId, 'peer-1');
      expect(got.single.messageId, isEmpty);
    });

    test('message tap: marks it read and opens at that message', () async {
      store.messages['m1'] = Message(
          id: 'm1', senderId: 'peer-1', recipientId: 'self-device',
          body: 'hi', createdAt: DateTime.utc(2026, 10, 30, 10));
      final got = await run(_open(
          notificationId:
              LocalLinkNotificationId.directMessage('peer-1', 'm1'),
          messageId: 'm1'));
      expect(got.single.messageId, 'm1');
      expect(store.markedRead, ['m1']);
    });

    test('message gone: still opens the chat (no focus)', () async {
      final got = await run(_open(
          notificationId:
              LocalLinkNotificationId.directMessage('peer-1', 'gone'),
          messageId: 'gone'));
      expect(got.single.conversationId, 'peer-1');
      expect(got.single.messageId, isEmpty);
    });

    test('blocked contact, unknown contact or foreign id: nothing opens',
        () async {
      store.blocked.add('peer-1');
      expect(
          await run(_open(
              notificationId:
                  LocalLinkNotificationId.directSummary('peer-1'))),
          isEmpty);
      store.blocked.clear();
      expect(
          await run(_open(
              conversationId: 'stranger',
              notificationId:
                  LocalLinkNotificationId.directSummary('stranger'))),
          isEmpty);
      expect(await run(_open(notificationId: 12345)), isEmpty,
          reason: 'not one of our ids for this chat');
    });

    test('cold start: an open made before the app listens is kept', () async {
      await service.handleActionForTest(_open(
          notificationId: LocalLinkNotificationId.directSummary('peer-1')));
      final got = <LocalLinkNotificationAction>[];
      final sub = service.openRequests.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      expect(got.single.conversationId, 'peer-1');
      await sub.cancel();
    });

    test('platform keeps a tap that arrives before anyone listens', () async {
      final platform = LocalLinkNotificationPlatform();
      await Future<void>.delayed(Duration.zero);
      final completer = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        actionsChannel,
        const StandardMethodCodec().encodeSuccessEnvelope(<String, Object>{
          'action': 'open',
          'notification_id': 7,
          'conversation_type': 'direct',
          'conversation_id': 'peer-1',
          'message_id': '',
          'sender_id': '',
          'recipient_id': '',
        }),
        (_) => completer.complete(),
      );
      await completer.future;
      final got = <LocalLinkNotificationAction>[];
      final sub = platform.actions.listen(got.add);
      await Future<void>.delayed(Duration.zero);
      expect(got.single.conversationId, 'peer-1');
      await sub.cancel();
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/directory_search_merge.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

DirectoryProfile _p(String id, String name) =>
    DirectoryProfile.fromMap({'user_id': id, 'display_name': name});

const _min = 60 * 1000;

void main() {
  setUp(FriendAddMemory.resetForTest);

  group('Part 5: search merge', () {
    test('saved first, then server, one card per account', () {
      final saved = [_p('u1', 'Safeer A'), _p('u2', 'Safeer B')];
      final server = [_p('u2', 'Safeer B (server)'), _p('u3', 'Safeer C')];
      final merged = mergeSearchResults(saved, server);
      expect(merged.map((p) => p.userId), ['u1', 'u2', 'u3']);
      // the saved (signed) copy wins
      expect(merged[1].displayName, 'Safeer B');
    });
    test('empty ids are dropped, empty lists are fine', () {
      expect(mergeSearchResults(const [], const []), isEmpty);
      expect(mergeSearchResults([_p('', 'x')], [_p('u1', 'y')]).length, 1);
    });
    test('log line has no names', () {
      final line = friendSearchLogLine(
          queryLength: 6, saved: 1, server: null, friendsAsked: true, shown: 1);
      expect(line, 'len=6 saved=1 server=off friends_asked=y shown=1');
      expect(
          friendSearchLogLine(
              queryLength: 3, saved: 0, server: 2, friendsAsked: false, shown: 2),
          'len=3 saved=0 server=2 friends_asked=n shown=2');
    });
  });

  group('Part 6: offline hint', () {
    tearDown(() => DirectorySearchInfo.serverReached = true);
    test('only when nothing found AND the server was not reached', () {
      DirectorySearchInfo.serverReached = false;
      expect(DirectorySearchInfo.showOfflineHint(noMatch: true), isTrue);
      expect(DirectorySearchInfo.showOfflineHint(noMatch: false), isFalse);
      DirectorySearchInfo.serverReached = true;
      expect(DirectorySearchInfo.showOfflineHint(noMatch: true), isFalse);
    });
    test('text', () {
      expect(DirectorySearchInfo.offlineHint,
          "Not found. Try again when you're online or near friends.");
    });
  });

  group('Part 4: Hello from someone new', () {
    test('policy: notice beats new, new gives the friend notice', () {
      expect(
          FriendHelloPolicy.incomingHelloAction(
              body: 'Hi', nowMs: 10 * _min, helloFromNewAtMs: 10 * _min),
          IncomingHelloAction.normal);
      expect(
          FriendHelloPolicy.incomingHelloAction(
              body: 'Hello 👋', nowMs: 10 * _min, helloFromNewAtMs: 10 * _min),
          IncomingHelloAction.friendNotice);
      expect(
          FriendHelloPolicy.incomingHelloAction(
              body: 'Hello 👋',
              nowMs: 10 * _min,
              noticeAtMs: 9 * _min,
              helloFromNewAtMs: 10 * _min),
          IncomingHelloAction.silent);
      // old "new" mark (over 2 min) -> normal message
      expect(
          FriendHelloPolicy.incomingHelloAction(
              body: 'Hello 👋', nowMs: 10 * _min, helloFromNewAtMs: 5 * _min),
          IncomingHelloAction.normal);
      // a friend's ordinary Hello (no marks) -> normal
      expect(
          FriendHelloPolicy.incomingHelloAction(body: 'Hello 👋', nowMs: 1),
          IncomingHelloAction.normal);
    });

    test('memory: noted Hello from new -> friend notice once, then silent', () {
      var t = 1000000;
      FriendAddMemory.now = () => t;
      FriendAddMemory.noteHelloFromNew('dev-s', userId: 'u-s', name: 'Sajjad');
      expect(FriendAddMemory.incomingHelloAction('dev-s', 'Hello 👋'),
          IncomingHelloAction.friendNotice);
      expect(FriendAddMemory.helloFromNew('dev-s')!.userId, 'u-s');
      expect(FriendAddMemory.helloFromNew('dev-s')!.name, 'Sajjad');
      // the service notes the notice when it shows it
      FriendAddMemory.noteNotice('dev-s');
      t += 1000;
      expect(FriendAddMemory.incomingHelloAction('dev-s', 'Hello 👋'),
          IncomingHelloAction.silent);
      // someone else is unaffected
      expect(FriendAddMemory.incomingHelloAction('dev-x', 'Hello 👋'),
          IncomingHelloAction.normal);
    });

    test('no user id -> nothing noted (Remove would not work)', () {
      FriendAddMemory.noteHelloFromNew('dev-s', userId: ' ');
      expect(FriendAddMemory.helloFromNew('dev-s'), isNull);
    });

    test('later friend link: still counts as new for 5 min after auto-add', () {
      expect(
          FriendHelloPolicy.treatAsNewFriend(
              wasContact: true, nowMs: 3 * _min, autoAddedAtMs: 1 * _min),
          isTrue);
    });
  });
}

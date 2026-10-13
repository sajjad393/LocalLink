import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/gradient_pill_button.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/messenger_date_divider.dart';
import 'package:locallink/features/groups/presentation/widgets/create_group_dialog.dart';
import 'package:locallink/features/groups/presentation/widgets/group_member_tile.dart';

Device _device(String id, String name) => Device(
      id: id,
      name: name,
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

GroupMember _member(String deviceId, String name, {String role = 'member'}) =>
    GroupMember(
      groupId: 'g1',
      deviceId: deviceId,
      role: role,
      joinedAt: '2026-01-01T00:00:00Z',
      name: name,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('GroupAvatar', () {
    testWidgets('renders the groups glyph on a brand-gradient circle',
        (tester) async {
      await tester.pumpWidget(_host(const GroupAvatar(radius: 24)));

      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.gradient, LocalLinkBrand.linearGradient);
    });
  });

  group('MessengerDateDivider', () {
    testWidgets('labels today as Today', (tester) async {
      await tester.pumpWidget(_host(MessengerDateDivider(date: DateTime.now())));
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('formats older dates as d/m/y', (tester) async {
      await tester.pumpWidget(
        _host(MessengerDateDivider(date: DateTime(2026, 1, 5))),
      );
      expect(find.text('5/1/2026'), findsOneWidget);
    });
  });

  group('CreateGroupDialog', () {
    testWidgets('create stays disabled until a name is entered',
        (tester) async {
      await tester.pumpWidget(
        _host(CreateGroupDialog(devices: [_device('d1', 'Ali')])),
      );

      final button = tester.widget<GradientPillButton>(
        find.byType(GradientPillButton),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField).first, 'Study group');
      await tester.pump();

      final enabled = tester.widget<GradientPillButton>(
        find.byType(GradientPillButton),
      );
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('lists devices with account avatars', (tester) async {
      await tester.pumpWidget(
        _host(CreateGroupDialog(devices: [_device('d1', 'Ali')])),
      );

      expect(find.text('Ali'), findsOneWidget);
      expect(find.byType(AccountAvatar), findsOneWidget);
    });
  });

  group('GroupMemberTile', () {
    testWidgets('shows an account avatar and an owner chip', (tester) async {
      await tester.pumpWidget(
        _host(
          GroupMemberTile(
            member: _member('d1', 'Ali', role: 'owner'),
            isOwner: true,
            canRemove: true,
          ),
        ),
      );

      expect(find.byType(AccountAvatar), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.byIcon(Icons.person_remove), findsNothing);
    });

    testWidgets('offers removal for non-owner members', (tester) async {
      var removed = false;
      await tester.pumpWidget(
        _host(
          GroupMemberTile(
            member: _member('d2', 'Sara'),
            isOwner: false,
            canRemove: true,
            onRemove: () => removed = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.person_remove));
      expect(removed, isTrue);
    });
  });
}

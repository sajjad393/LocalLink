import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_card.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(theme: LocalLinkTheme.light(), home: Scaffold(body: child));
  }

  testWidgets('primary button renders and invokes callback', (tester) async {
    var pressed = false;
    await tester.pumpWidget(
      wrap(LocalLinkButton(label: 'Continue', onPressed: () => pressed = true)),
    );

    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    expect(pressed, isTrue);
  });

  testWidgets('text field uses the shared input styling', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      wrap(LocalLinkTextField(controller: controller, labelText: 'Name')),
    );

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
  });

  testWidgets('card and info card render shared content', (tester) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: const [
            LocalLinkCard(child: Text('Card content')),
            SizedBox(height: 8),
            LocalLinkInfoCard(
              icon: Icon(Icons.info_outline),
              title: 'Title',
              message: 'Message',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Card content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('empty and error states render reusable feedback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Column(
          children: [
            Expanded(
              child: LocalLinkEmptyView(
                icon: Icons.inbox_outlined,
                title: 'Nothing here',
                message: 'Try again later.',
              ),
            ),
            LocalLinkErrorText(message: 'Something went wrong'),
          ],
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Try again later.'), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
  });
}

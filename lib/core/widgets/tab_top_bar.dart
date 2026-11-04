import 'package:flutter/material.dart';

/// Bundle 183 (L): the ONE top bar of the 4 tabs (Chats, Calls, People,
/// Settings). Title only, on the left, same place and size on every tab,
/// never a back arrow (the tabs are the app's main screen - the old arrow
/// on People / Settings closed the app on the second tap).
class TabTopBar extends StatelessWidget implements PreferredSizeWidget {
  /// Usually a `Text`; Chats wraps it for the hidden 5 taps (180).
  final Widget title;

  /// Bundle 207 (L1): e.g. the Chats search icon. Empty = title only.
  final List<Widget> actions;

  const TabTopBar(
      {super.key, required this.title, this.actions = const <Widget>[]});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      key: const ValueKey('tab_top_bar'),
      automaticallyImplyLeading: false,
      leading: null,
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      toolbarHeight: kToolbarHeight,
      title: title,
      actions: actions,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';

/// Bundle 298 (B): one search look in the whole app, the same as the Add
/// Contact search (283): a grey pill; while typing it turns lighter and gets a
/// 2 dp round blue ring. The text box inside never draws its own line (the
/// app theme gives every field a blue focus box - that drew a square inside
/// the pill).
class SearchPill298 extends StatefulWidget {
  const SearchPill298({
    super.key,
    required this.controller,
    required this.hint,
    this.fieldKey,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.height = 44,
    this.trailing,
    this.clearButton = false,
    this.textInputAction = TextInputAction.search,
  });

  final TextEditingController controller;
  final String hint;

  /// Key of the text field (old tests find the field by it).
  final Key? fieldKey;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final double height;

  /// Shown at the right end (a filter button, a clear X ...).
  final Widget? trailing;

  /// An X that clears the text (shown only while there is text).
  final bool clearButton;
  final TextInputAction textInputAction;

  /// No line of its own, in any state: the pill draws the ring.
  static const InputDecoration bare = InputDecoration(
    isCollapsed: true,
    filled: false,
    // The theme's padding would push the words away from the search icon.
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );

  @override
  State<SearchPill298> createState() => _SearchPill298State();
}

class _SearchPill298State extends State<SearchPill298> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_redraw);
    widget.controller.addListener(_redraw);
  }

  @override
  void didUpdateWidget(covariant SearchPill298 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_redraw);
      widget.controller.addListener(_redraw);
    }
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_redraw);
    _focus
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = LinkKit.of(context);
    final focused = _focus.hasFocus;
    final hasText = widget.controller.text.isNotEmpty;
    // Same colours as SearchBox283 (Add Contact).
    final bg = focused
        ? (p.isDark ? const Color(0xFF1B1D26) : Colors.white)
        : (p.isDark ? const Color(0xFF1F2027) : const Color(0xFFECEEF4));
    final hint = p.isDark ? const Color(0xFF8E91A0) : const Color(0xFF6B7080);
    final iconColor = focused ? (p.isDark ? const Color(0xFFC9CBD6) : const Color(0xFF374151)) : hint;
    final size = widget.height >= 48 ? 14.5 : 14.0;
    return AnimatedContainer(
      key: const ValueKey('search_pill_298'),
      duration: const Duration(milliseconds: 180),
      height: widget.height,
      padding: EdgeInsets.only(left: 14, right: widget.trailing != null || widget.clearButton ? 4 : 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(widget.height / 2),
        border: Border.all(color: focused ? p.focus : Colors.transparent, width: 2),
      ),
      child: Row(children: [
        Icon(Icons.search, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            textInputAction: widget.textInputAction,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            cursorColor: p.focus,
            cursorWidth: 2,
            style: TextStyle(fontSize: size, color: p.text),
            decoration: SearchPill298.bare.copyWith(
              hintText: widget.hint,
              hintStyle: TextStyle(fontSize: size, color: hint),
            ),
          ),
        ),
        if (widget.clearButton && hasText)
          IconButton(
            tooltip: 'Clear',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              widget.controller.clear();
              widget.onChanged?.call('');
            },
            icon: Icon(Icons.close, size: 20, color: iconColor),
          ),
        if (widget.trailing != null) widget.trailing!,
      ]),
    );
  }
}

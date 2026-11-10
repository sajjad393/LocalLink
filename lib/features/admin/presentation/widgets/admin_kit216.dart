import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/presentation/theme/admin_ui216.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';

export 'package:locallink/core/widgets/admin_crown.dart'
    show CrownPainter216, AdminRoleTag216;
export 'package:locallink/features/admin/presentation/theme/admin_ui216.dart';

/// Bundle 216: the shared widgets of the redesigned admin pages
/// (UI_SPEC_216 §2). Sizes, colours and text styles come from §1.

// ---------------------------------------------------------------- 1. page

/// Scaffold with the 60 dp app bar and a padded ListView body.
class AdminPage216 extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? right;
  final List<Widget> children;

  /// Body built by the caller instead of [children] (map, custom scroll).
  final Widget? body;
  /// Bundle 254 (21.8): a bar pinned under the title (outside the list, 8 dp
  /// top space) so a scroll or pull-to-refresh never hides it.
  final Widget? pinned;
  final bool back;

  /// 216d: server pages lock while the server is lost.
  final bool needsServer;
  final AppViewModeCubit? viewMode;
  final String module;
  final Future<void> Function()? onServerBack;
  final Future<void> Function()? onRefresh;

  const AdminPage216({
    super.key,
    required this.title,
    this.subtitle,
    this.right,
    this.children = const [],
    this.body,
    this.pinned,
    this.back = true,
    this.needsServer = false,
    this.viewMode,
    this.module = '',
    this.onServerBack,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    Widget content = body ??
        ListView(
          key: const ValueKey('a216_list'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: children,
        );
    if (onRefresh != null && body == null) {
      content = RefreshIndicator(onRefresh: onRefresh!, child: content);
    }
    if (pinned != null) {
      content = Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: pinned!),
        Expanded(child: content),
      ]);
    }
    if (needsServer && viewMode != null) {
      content = ServerLockGate(
          viewMode: viewMode!,
          module: module.isEmpty ? title : module,
          onServerBack: onServerBack,
          child: content);
    }
    return AdminTheme216Scope(
      child: Builder(
        builder: (context) => Scaffold(
          key: const ValueKey('a216_page'),
          backgroundColor: c.bg,
          body: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AdminAppBar216(
                    title: title,
                    subtitle: subtitle,
                    right: right,
                    back: back,
                    viewMode: needsServer ? viewMode : null),
                const AdminUiCheckBanner216(),
                const ServerClockBar255(),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bundle 255 A3: pinned warning while the server PC clock is over 1 h off.
class ServerClockBar255 extends StatelessWidget {
  const ServerClockBar255({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration?>(
        valueListenable: ServerClock255.wrong,
        builder: (context, offset, _) => offset == null
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('server_clock_bar_255'),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF0C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFEC84B)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 20, color: Color(0xFFB54708)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ServerClock255.title(offset),
                              style: const TextStyle(
                                  fontFamily: 'Roboto216',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF93370D))),
                          const SizedBox(height: 2),
                          const Text(ServerClock255.body,
                              style: TextStyle(
                                  fontFamily: 'Roboto216',
                                  fontSize: 12.5,
                                  color: Color(0xFF93370D))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      );
}

/// The 60 dp app bar (§1.5). With [viewMode] the subtitle turns into
/// `Last updated H:mm` while the server is lost.
class AdminAppBar216 extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? right;
  final bool back;
  final AppViewModeCubit? viewMode;

  const AdminAppBar216({
    super.key,
    required this.title,
    this.subtitle,
    this.right,
    this.back = true,
    this.viewMode,
  });

  @override
  State<AdminAppBar216> createState() => _AdminAppBar216State();
}

class _AdminAppBar216State extends State<AdminAppBar216> {
  StreamSubscription<AppViewModeState>? _sub;
  bool _lost = false;
  DateTime _last = DateTime.now();

  @override
  void initState() {
    super.initState();
    final vm = widget.viewMode;
    if (vm != null) {
      _lost = !vm.state.serverConnected;
      _sub = vm.stream.listen((s) {
        if (!mounted) return;
        final lost = !s.serverConnected;
        if (lost == _lost) return;
        setState(() {
          if (lost) _last = DateTime.now();
          _lost = lost;
        });
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final sub = _lost
        ? 'Last updated ${_last.hour}:${_last.minute.toString().padLeft(2, '0')}'
        : widget.subtitle;
    final canPop = widget.back && Navigator.of(context).canPop();
    return SizedBox(
      height: A216.appBarHeight,
      child: Stack(children: [
        if (canPop)
          Positioned(
            left: 4,
            top: 8,
            child: IconButton(
              key: const ValueKey('a216_back'),
              tooltip: 'Back',
              icon: Icon(Icons.arrow_back_rounded, size: 22, color: c.ink),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        Positioned(
          left: canPop ? 54 : 16,
          right: widget.right == null ? 16 : 64,
          top: 0,
          bottom: 0,
          child: sub == null || sub.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(widget.title,
                      key: const ValueKey('a216_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.appBarTitle),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 9),
                    Text(widget.title,
                        key: const ValueKey('a216_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.appBarTitleSub),
                    const SizedBox(height: 1.4),
                    Text(sub,
                        key: const ValueKey('a216_subtitle'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.appBarSub),
                  ],
                ),
        ),
        if (widget.right != null)
          Positioned(
            right: 12,
            top: 12,
            child: SizedBox(width: 36, height: 36, child: widget.right),
          ),
      ]),
    );
  }
}

/// 36 dp round app-bar action.
class AdminBarAction216 extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? fill;
  final bool border;

  const AdminBarAction216({
    super.key,
    required this.child,
    this.onTap,
    this.tooltip,
    this.fill,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final w = Material(
      color: fill ?? c.surface,
      shape: CircleBorder(
          side: border ? BorderSide(color: c.line) : BorderSide.none),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Center(child: child))),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

// ------------------------------------------------------------- 2. section

class AdminSection216 extends StatelessWidget {
  final String text;
  final String? right;
  final Color? rightColor;
  final Key? rightKey;
  final double top;

  const AdminSection216(this.text,
      {super.key, this.right, this.rightColor, this.rightKey, this.top = 18});

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: 24,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: 4),
            Expanded(
                child: Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.section)),
            if (right != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(right!,
                    key: rightKey,
                    style: t.sectionRight
                        .copyWith(color: rightColor ?? t.sectionRight.color)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 3. card

class AdminCard216 extends StatelessWidget {
  final Widget child;
  final Color? fill;
  final Color? border;
  final bool shadow;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double? height;

  const AdminCard216({
    super.key,
    required this.child,
    this.fill,
    this.border,
    this.shadow = true,
    this.radius = 16,
    this.padding,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    // Bundle 254 (21.6): clip the CARD (padding included), not the padded
    // content, so a title in the top-left corner is never cut by the curve.
    return Container(
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fill ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? c.line),
        boxShadow: shadow && !c.dark ? const [A216.cardShadow] : null,
      ),
      child: child,
    );
  }
}

/// Grey note card (no shadow), 12 / grey text.
class AdminNote216 extends StatelessWidget {
  final String text;
  final bool card;
  final TextAlign align;
  const AdminNote216(this.text,
      {super.key, this.card = true, this.align = TextAlign.start});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final body = Text(text, textAlign: align, style: t.note);
    if (!card) return body;
    return AdminCard216(
      fill: c.surfaceSoft,
      shadow: false,
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: SizedBox(width: double.infinity, child: body),
    );
  }
}

// ----------------------------------------------------------- 4. list card

/// Hides the trailing chevron of an [AdminRow216].
abstract final class A216Trailing {
  static const Widget none = SizedBox.shrink(key: ValueKey('a216_no_trailing'));
}

class AdminRow216 {
  final Key? key;
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? trailing;
  final double height;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? titleColor;
  final Color? subtitleColor;

  const AdminRow216({
    this.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.height = A216.rowMenu,
    this.onTap,
    this.enabled = true,
    this.titleColor,
    this.subtitleColor,
  });
}

class AdminListCard216 extends StatelessWidget {
  final List<AdminRow216> rows;
  final Color? fill;
  final bool shadow;

  const AdminListCard216(this.rows, {super.key, this.fill, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final textStart = r.leading == null ? 16.0 : 60.0;
      final trailing = r.trailing ??
          Icon(Icons.chevron_right_rounded, size: 16, color: c.grey2);
      children.add(Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: r.key,
          onTap: r.enabled ? r.onTap : null,
          child: SizedBox(
            height: r.height,
            child: Stack(children: [
              if (r.leading != null)
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  width: 40,
                  child: Center(child: r.leading),
                ),
              Positioned(
                left: textStart,
                right: 0,
                top: 0,
                bottom: 0,
                child: Row(children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.rowTitle.copyWith(
                                color: r.titleColor ??
                                    (r.enabled ? c.ink : c.grey2))),
                        if (r.subtitle != null && r.subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(r.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.rowSub.copyWith(
                                  color: r.subtitleColor ??
                                      (r.enabled ? c.grey : c.grey2))),
                        ],
                        if (r.subtitleWidget != null) ...[
                          const SizedBox(height: 3),
                          r.subtitleWidget!,
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  trailing,
                  SizedBox(width: r.trailing == null ? 18 : 14),
                ]),
              ),
              if (i < rows.length - 1)
                Positioned(
                  left: textStart,
                  right: 0,
                  bottom: 0,
                  height: 1,
                  child: ColoredBox(color: c.div),
                ),
            ]),
          ),
        ),
      ));
    }
    return AdminCard216(
      fill: fill,
      shadow: shadow,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ----------------------------------------------------------- 5. tone icon

class AdminToneIcon216 extends StatelessWidget {
  final IconData icon;
  final A216Tone tone;
  final double radius;
  final double size;
  final Color? bg;
  final Color? fg;

  const AdminToneIcon216(this.icon, this.tone,
      {super.key, this.radius = 18, this.size = 19, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration:
          BoxDecoration(color: bg ?? c.toneBg(tone), shape: BoxShape.circle),
      child: Icon(icon, size: size, color: fg ?? c.toneFg(tone)),
    );
  }
}

// ----------------------------------------------------------------- 6. tag

class AdminTag216 extends StatelessWidget {
  final String text;
  final A216Tone tone;
  final bool dot;
  final Color? bg;
  final Color? fg;

  const AdminTag216(this.text, this.tone,
      {super.key, this.dot = false, this.bg, this.fg});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final f = fg ?? c.toneFg(tone);
    return Container(
      height: A216.tagHeight,
      padding: EdgeInsets.only(left: dot ? 8 : 8, right: 8),
      decoration: BoxDecoration(
          color: bg ?? c.toneBg(tone),
          borderRadius: BorderRadius.circular(10.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: f, shape: BoxShape.circle)),
          const SizedBox(width: 4),
        ],
        Text(text, style: A216Text(c).tag(f)),
      ]),
    );
  }
}

// --------------------------------------------------------- 7. pill button

class AdminPillButton216 extends StatelessWidget {
  final String text;
  final A216Tone tone;
  final VoidCallback? onTap;

  const AdminPillButton216(this.text, this.tone, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Material(
      color: c.toneBg(tone),
      borderRadius: BorderRadius.circular(15),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: A216.pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Text(text, style: A216Text(c).pillBtn(c.toneFg(tone))),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 8. chips

class AdminChips216 extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<Key>? keys;
  final bool wrap;

  const AdminChips216({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.keys,
    this.wrap = false,
  });

  Widget _chip(BuildContext context, int i) {
    final c = A216.colors(context);
    final on = i == selected;
    return Material(
      key: keys != null && i < keys!.length ? keys![i] : null,
      color: on ? c.blueSel : c.surface,
      shape: StadiumBorder(
          side: BorderSide(color: on ? c.blueSelBorder : c.ctrlBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onSelected(i),
        child: Container(
          height: A216.chipHeight,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          child: Text(items[i], style: A216Text(c).chip(on)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (wrap) {
      return Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 0; i < items.length; i++) _chip(context, i),
      ]);
    }
    return SizedBox(
      height: A216.chipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: _chip,
      ),
    );
  }
}

// --------------------------------------------------------------- 9. search

class AdminSearch216 extends StatelessWidget {
  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;

  const AdminSearch216({
    super.key,
    required this.hint,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.fieldKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Container(
      height: A216.searchHeight,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line),
      ),
      child: Row(children: [
        const SizedBox(width: 13),
        Icon(Icons.search_rounded, size: 18, color: c.grey),
        const SizedBox(width: 11),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            textInputAction: TextInputAction.search,
            style: t.search,
            cursorColor: c.blue,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: t.searchHint,
            ),
          ),
        ),
        const SizedBox(width: 14),
      ]),
    );
  }
}

// -------------------------------------------------------------- 10. button

enum A216ButtonKind { primary, danger, tonal, outline }

class AdminButton216 extends StatelessWidget {
  final String text;
  final A216ButtonKind kind;
  final IconData? icon;
  final double height;
  final double? width;
  final VoidCallback? onTap;

  const AdminButton216(
    this.text, {
    super.key,
    this.kind = A216ButtonKind.primary,
    this.icon,
    this.height = A216.buttonHeight,
    this.width,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final (Color fill, Color fg, BorderSide side) = switch (kind) {
      A216ButtonKind.primary => (c.blue, Colors.white, BorderSide.none),
      A216ButtonKind.danger => (c.red, Colors.white, BorderSide.none),
      A216ButtonKind.tonal => (c.blueSel, c.blue, BorderSide.none),
      A216ButtonKind.outline =>
        (c.surface, c.ink2, BorderSide(color: c.ctrlBorder)),
    };
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: fill,
        shape: StadiumBorder(side: side),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            width: width,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: A216Text(c).button(fg)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- 11. radio card

class AdminRadio216 extends StatelessWidget {
  final bool on;
  const AdminRadio216(this.on, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on ? c.blue : c.grey2, width: 1.8),
      ),
      alignment: Alignment.center,
      child: on
          ? Container(
              width: 9.6,
              height: 9.6,
              decoration: BoxDecoration(color: c.blue, shape: BoxShape.circle))
          : null,
    );
  }
}

class AdminRadioCard216 extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;
  final double height;
  final bool sheet;

  const AdminRadioCard216({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    this.onTap,
    this.trailing,
    this.height = 60,
    this.sheet = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Opacity(
      opacity: onTap == null && !selected ? 0.6 : 1,
      child: Material(
        color: selected ? c.blueCard : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
              color: selected ? c.blue : c.line, width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: height,
            child: Row(children: [
              const SizedBox(width: 14),
              AdminRadio216(selected),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: sheet ? t.radioTitleSheet : t.radioTitle),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.radioSub),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 12)],
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- 12. stepper

class AdminStepper216 extends StatelessWidget {
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final double width;
  final Key? minusKey;
  final Key? plusKey;

  const AdminStepper216({
    super.key,
    required this.value,
    this.onMinus,
    this.onPlus,
    this.width = 104,
    this.minusKey,
    this.plusKey,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    Widget part(IconData icon, VoidCallback? onTap, Key? key) => InkWell(
          key: key,
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 32,
            child: Icon(icon,
                size: 15, color: onTap == null ? c.grey2 : c.ink2),
          ),
        );
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.ctrlBorder)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: 32,
        child: Row(children: [
          part(Icons.remove_rounded, onMinus, minusKey),
          Container(width: 1, color: c.ctrlBorder),
          Expanded(
            child: Center(
              child: Text(value,
                  maxLines: 1,
                  style: A216Text(c).custom(13.5, FontWeight.w600, c.ink, 1)),
            ),
          ),
          Container(width: 1, color: c.ctrlBorder),
          part(Icons.add_rounded, onPlus, plusKey),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- 13. switch

class A216Switch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const A216Switch({super.key, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 24,
          decoration: BoxDecoration(
            color: value ? c.blue : c.ctrlBorder,
            borderRadius: BorderRadius.circular(12),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.all(2.5),
              width: 19,
              height: 19,
              decoration: const BoxDecoration(
                  color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------- 14. stat tile

class AdminStatTile216 extends StatelessWidget {
  final String big;
  final String small;
  final A216Tone tone;
  final IconData icon;
  final Key? valueKey;

  const AdminStatTile216(this.big, this.small, this.tone, this.icon,
      {super.key, this.valueKey});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return AdminCard216(
      height: 78,
      child: Stack(children: [
        Positioned(
            left: 11, top: 11, child: AdminToneIcon216(icon, tone, radius: 13, size: 15)),
        Positioned(
          left: 12,
          right: 8,
          bottom: 30 - 19 * 0.2,
          child: Text(big,
              key: valueKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.statBig),
        ),
        Positioned(
          left: 12,
          right: 8,
          bottom: 12 - 11.5 * 0.25,
          child: Text(small,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: t.statSmall),
        ),
      ]),
    );
  }
}

/// Tiles in rows of [perRow] with a 10 dp gap.
class AdminStatGrid216 extends StatelessWidget {
  final List<Widget> tiles;
  final int perRow;
  const AdminStatGrid216(this.tiles, {super.key, this.perRow = 3});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += perRow) {
      final part = tiles.sublist(i, math.min(i + perRow, tiles.length));
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(Row(children: [
        for (var j = 0; j < perRow; j++) ...[
          if (j > 0) const SizedBox(width: 10),
          Expanded(child: j < part.length ? part[j] : const SizedBox()),
        ],
      ]));
    }
    return Column(children: rows);
  }
}

// ---------------------------------------------------------------- 15. hero

class AdminHeroCard216 extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String sub;
  final bool online;
  final String wayText;
  final String near;
  final String blocked;
  final String minVersion;

  const AdminHeroCard216({
    super.key,
    required this.avatar,
    required this.name,
    required this.sub,
    required this.online,
    required this.wayText,
    required this.near,
    required this.blocked,
    required this.minVersion,
  });

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    Widget stat(String n, String label, Key key) => Expanded(
          child: Column(children: [
            const SizedBox(height: 14),
            SizedBox(
              height: 24,
              child: Center(
                  child: Text(n,
                      key: key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heroNumber)),
            ),
            const SizedBox(height: 6),
            Text(label, style: t.heroLabel),
          ]),
        );
    Widget vline() => Container(
        width: 1, height: 50, color: A216.heroDivider);
    return Container(
      key: const ValueKey('a216_hero'),
      height: 168,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(A216.heroRadius),
        gradient: const LinearGradient(colors: [A216.heroFrom, A216.heroTo]),
        boxShadow: const [A216.heroShadow],
      ),
      child: Stack(children: [
        Positioned(left: 18, top: 24, width: 44, height: 44, child: Center(child: avatar)),
        Positioned(
          left: 74,
          right: 14,
          top: 24,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heroName),
                  const SizedBox(height: 5),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heroSub),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              key: const ValueKey('a216_way_chip'),
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                  color: A216.heroChip,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: online ? A216.heroOnline : A216.heroOffline,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(wayText,
                    style: t.custom(11.5, FontWeight.w600, Colors.white, 1)),
              ]),
            ),
          ]),
        ),
        const Positioned(
          left: 16,
          right: 16,
          top: 86,
          height: 1,
          child: ColoredBox(color: A216.heroDivider),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 87,
          bottom: 0,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            stat(near, 'Phones near', const ValueKey('a216_stat_near')),
            Padding(padding: const EdgeInsets.only(top: 13), child: vline()),
            stat(blocked, 'Blocked', const ValueKey('a216_stat_blocked')),
            Padding(padding: const EdgeInsets.only(top: 13), child: vline()),
            stat(minVersion, 'Min. version', const ValueKey('a216_stat_min')),
          ]),
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- 16. banner

enum A216BannerKind { warning, success, info }

class AdminBanner216 extends StatelessWidget {
  final A216BannerKind kind;
  final String title;
  final String? body;
  final IconData? icon;

  const AdminBanner216(this.kind, this.title,
      {super.key, this.body, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    final (Color fill, Color border, Color ic, Color tc, Color bc) =
        switch (kind) {
      A216BannerKind.warning => (
          const Color(0xFFFFFAEB),
          const Color(0xFFFEDF89),
          const Color(0xFFB54708),
          const Color(0xFF93370D),
          const Color(0xFFB54708)
        ),
      A216BannerKind.success => (
          const Color(0xFFECFDF3),
          const Color(0xFFABEFC6),
          const Color(0xFF12B76A),
          const Color(0xFF067647),
          const Color(0xFF067647)
        ),
      A216BannerKind.info => (
          const Color(0xFFEFF4FF),
          const Color(0xFFD1E0FF),
          const Color(0xFF1E5BFF),
          const Color(0xFF1D3A8A),
          const Color(0xFF3B5BB5)
        ),
    };
    final lead = kind == A216BannerKind.success
        ? Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(color: ic, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, size: 14, color: Colors.white))
        : Icon(
            icon ??
                (kind == A216BannerKind.warning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded),
            size: 20,
            color: ic);
    return Container(
      constraints: BoxConstraints(
          minHeight: kind == A216BannerKind.success ? 50 : 62),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: body == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.custom(13.5, FontWeight.w600, tc, 1.25)),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: t.custom(12, FontWeight.w400, bc, 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- 17. empty state

class AdminEmptyState216 extends StatelessWidget {
  final IconData icon;
  final A216Tone tone;
  final String title;
  final String body;
  final String? button;
  final VoidCallback? onButton;
  final bool card;

  const AdminEmptyState216({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    this.button,
    this.onButton,
    this.card = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    final inner = Padding(
      padding: const EdgeInsets.fromLTRB(25, 24, 25, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdminToneIcon216(icon, tone, radius: 36, size: 32),
          const SizedBox(height: 16),
          Text(title,
              key: const ValueKey('a216_empty_title'),
              textAlign: TextAlign.center,
              style: t.emptyTitle),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center, style: t.emptyBody),
          if (button != null) ...[
            const SizedBox(height: 16),
            AdminButton216(button!,
                key: const ValueKey('a216_empty_button'),
                kind: A216ButtonKind.tonal,
                height: 40,
                width: 160,
                onTap: onButton),
          ],
        ],
      ),
    );
    return KeyedSubtree(
      key: const ValueKey('a216_empty'),
      child: card
          ? AdminCard216(child: SizedBox(width: double.infinity, child: inner))
          : inner,
    );
  }
}

// --------------------------------------------------------------- 18. sheet

/// Bottom sheet with the 216 look (radius 28, handle, padding).
Future<T?> showAdminSheet216<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scroll = true,
}) {
  final c = A216.colors(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.surface,
    barrierColor: A216.barrier,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => AdminTheme216Scope(
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: c.ctrlBorder,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Flexible(
              child: scroll
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                      child: builder(ctx))
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
                      child: builder(ctx)),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Yes / no question in the 216 look. Returns true on [yes].
Future<bool> confirmAdmin216(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  bool danger = false,
  Key? yesKey,
}) async {
  final r = await showAdminSheet216<bool>(context, builder: (ctx) {
    final t = A216Text.of(ctx);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.sheetTitle),
        const SizedBox(height: 8),
        Text(body, style: t.rowSub.copyWith(height: 1.4)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: AdminButton216('Cancel',
                kind: A216ButtonKind.outline,
                height: 42,
                onTap: () => Navigator.of(ctx).pop(false)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AdminButton216(yes,
                key: yesKey ?? const ValueKey('a216_confirm_yes'),
                kind: danger ? A216ButtonKind.danger : A216ButtonKind.primary,
                height: 42,
                onTap: () => Navigator.of(ctx).pop(true)),
          ),
        ]),
      ],
    );
  });
  return r == true;
}

void adminSnack216(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

// --------------------------------------------------------- 19. locked rows

class AdminLockedItem216 {
  final String module;
  final String title;
  final IconData icon;
  const AdminLockedItem216(this.module, this.title, this.icon);
}

class AdminLockedRows216 extends StatelessWidget {
  final List<AdminLockedItem216> items;
  const AdminLockedRows216(this.items, {super.key});

  static const String note =
      'Needs the server. It opens by itself when the server is back.';

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return AdminListCard216(
      [
        for (final it in items)
          AdminRow216(
            key: ValueKey('a216_locked_${it.module}'),
            height: 54,
            leading: AdminToneIcon216(it.icon, A216Tone.grey,
                bg: c.div, fg: c.grey2),
            title: it.title,
            subtitle: 'Needs the server',
            titleColor: c.grey2,
            subtitleColor: c.grey2,
            trailing: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.lock_outline_rounded, size: 17, color: c.grey2),
            ),
            onTap: () => adminSnack216(context, note),
          ),
      ],
      fill: c.surfaceMuted,
      shadow: false,
    );
  }
}

// ---------------------------------------------------------- 20. lock gate

/// 216d: greys a server page while the server is lost (last data stays),
/// blocks taps, and lifts by itself when the server is back (then the
/// page reloads once through [onServerBack]).
class ServerLockGate extends StatefulWidget {
  final AppViewModeCubit viewMode;
  final String module;
  final Widget child;
  final Future<void> Function()? onServerBack;

  const ServerLockGate({
    super.key,
    required this.viewMode,
    required this.module,
    required this.child,
    this.onServerBack,
  });

  static String wayOf(AppViewModeState s) => s.serverConnected ? 'server' : 'none';

  @override
  State<ServerLockGate> createState() => _ServerLockGateState();
}

class _ServerLockGateState extends State<ServerLockGate> {
  StreamSubscription<AppViewModeState>? _sub;
  late bool _locked = !widget.viewMode.state.serverConnected;

  @override
  void initState() {
    super.initState();
    _sub = widget.viewMode.stream.listen((s) {
      final locked = !s.serverConnected;
      if (!mounted || locked == _locked) return;
      AppLogger.info('ADMIN_LOCK',
          detail: '${locked ? 'on' : 'off'} way=${locked ? 'offline' : 'server'} page=${widget.module}');
      setState(() => _locked = locked);
      if (!locked) {
        final back = widget.onServerBack;
        if (back != null) unawaited(back().catchError((_) {}));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Stack(children: [
      Positioned.fill(
          child: AbsorbPointer(absorbing: _locked, child: widget.child)),
      if (_locked) ...[
        Positioned.fill(
          child: IgnorePointer(
              child: ColoredBox(color: c.bg.withValues(alpha: 0.65))),
        ),
        Positioned(
          left: 14,
          right: 14,
          top: 70,
          child: AdminCard216(
            key: const ValueKey('a216_lock_card'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminToneIcon216(
                    Icons.lock_outline_rounded, A216Tone.orange,
                    radius: 20, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Server lost',
                          style: t.custom(15, FontWeight.w600, c.ink, 1.25)),
                      const SizedBox(height: 4),
                      Text(
                          'This page is locked. It opens again by itself when the server is back.',
                          style: t.note),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}

// --------------------------------------------------------- 21. avatar

/// Photo + crown A + blocked ring + online dot (§2.21).
class AdminPersonAvatar216 extends StatelessWidget {
  final String name;
  final String? userId;
  final String? deviceId;
  final double radius;
  final bool admin;
  final bool blocked;
  final bool online;

  /// Colour behind the photo (card colour).
  final Color? background;

  /// Server photo (admin avatar route) when the phone has none.
  final ImageProvider? photo;

  /// False = never draw the crown here (the caller wraps it in AdminCrown).
  final bool crown;

  /// Bundle 254 (21.5): the map labels me "You"; the letter / colour / photo
  /// must still come from my real name (same as the top card), not "Y".
  static String youName = '';
  static void noteYouName(String n) {
    final v = n.trim();
    if (v.isNotEmpty && v != 'You') youName = v;
  }

  String get _shownName => name == 'You' && youName.isNotEmpty ? youName : name;

  const AdminPersonAvatar216({
    super.key,
    required this.name,
    this.userId,
    this.deviceId,
    this.radius = 20,
    this.admin = false,
    this.blocked = false,
    this.online = false,
    this.background,
    this.photo,
    this.crown = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final bg = background ?? c.surface;
    final server = this.photo;
    Widget photo = server != null
        ? CircleAvatar(
            key: const ValueKey('a216_server_photo'),
            radius: radius,
            backgroundColor: c.div,
            backgroundImage: server)
        : AccountAvatar(
            name: _shownName,
            radius: radius,
            peerId: deviceId ?? userId,
            userId: userId,
            crown: false,
          );
    if (blocked) {
      photo = Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        Positioned(
          left: -3.6,
          top: -3.6,
          right: -3.6,
          bottom: -3.6,
          child: Container(
            key: const ValueKey('a216_blocked_ring'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: A216.blockedRed, width: 2.6),
            ),
            padding: const EdgeInsets.all(1),
          ),
        ),
        ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: photo,
        ),
      ]);
    }
    if (online) {
      final r = math.max(3.5, radius * 0.2);
      photo = Stack(clipBehavior: Clip.none, children: [
        photo,
        Positioned(
          left: radius + radius * 0.72 - r - 1.8,
          top: radius + radius * 0.72 - r - 1.8,
          child: Container(
            key: const ValueKey('a216_online_dot'),
            width: (r + 1.8) * 2,
            height: (r + 1.8) * 2,
            decoration: BoxDecoration(
              color: A216.online,
              shape: BoxShape.circle,
              border: Border.all(color: bg, width: 1.8),
            ),
          ),
        ),
      ]);
    }
    final showCrown = crown && admin && !blocked ||
        crown &&
        (!blocked &&
            ((userId ?? '').isNotEmpty || (deviceId ?? '').isNotEmpty) &&
            AdminCrown.showFor(userId, deviceId));
    if (showCrown) {
      return AdminCrown.decorate(radius: radius, child: photo, background: bg);
    }
    return photo;
  }
}

// -------------------------------------------------------------- 24. legend

class LinkLegend216 extends StatelessWidget {
  final Set<A216Link> links;
  final bool anyBlocked;
  const LinkLegend216({super.key, required this.links, this.anyBlocked = false});

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    const order = [A216Link.server, A216Link.wifiDirect, A216Link.mesh, A216Link.lan];
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final l in order)
          if (links.contains(l))
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: A216.linkColor(l), shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(A216.linkLabel(l), style: t.legend),
            ]),
        if (anyBlocked)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: A216.linkBlocked,
                    shape: BoxShape.circle,
                    border: Border.all(color: A216.blockedRed, width: 1.4))),
            const SizedBox(width: 5),
            Text('Blocked · relays only', style: t.legend),
          ]),
      ],
    );
  }
}

// ------------------------------------------------------------ 25. timeline

class AdminTimelineItem216 {
  final IconData icon;
  final A216Tone tone;
  final String title;
  final String sub;
  final String day;
  const AdminTimelineItem216(
      {required this.icon,
      required this.tone,
      required this.title,
      required this.sub,
      required this.day});
}

class AdminTimeline216 extends StatelessWidget {
  final List<AdminTimelineItem216> items;
  const AdminTimeline216(this.items, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final out = <Widget>[];
    String? day;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.day != day) {
        day = it.day;
        out.add(SizedBox(
          height: 22,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(it.day, style: t.dayLabel),
            ),
          ),
        ));
      }
      final lastOfDay = i == items.length - 1 || items[i + 1].day != it.day;
      out.add(SizedBox(
        height: 58,
        child: Stack(children: [
          if (!lastOfDay)
            Positioned(
              left: 32 - 0.75,
              top: 30,
              bottom: 0,
              width: 1.5,
              child: ColoredBox(color: c.line),
            ),
          Positioned(
              left: 17, top: 0, child: AdminToneIcon216(it.icon, it.tone, radius: 15, size: 15)),
          Positioned(
            left: 58,
            right: 14,
            top: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.custom(13.5, FontWeight.w500, c.ink, 1.2)),
                const SizedBox(height: 3),
                Text(it.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.cardSub),
              ],
            ),
          ),
        ]),
      ));
    }
    return AdminCard216(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out),
    );
  }
}

// ------------------------------------------------------------- 26. bar row

class AdminBarRow216 extends StatelessWidget {
  final String label;

  /// 0..100, or null when the server did not send it.
  final double? value;
  final double? alert;

  const AdminBarRow216(this.label, this.value, this.alert, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final v = value;
    final color = v == null
        ? A216.barOk
        : v > 95
            ? A216.barBad
            : (alert != null && v > alert!)
                ? A216.barWarn
                : A216.barOk;
    return SizedBox(
      height: 52,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: t.custom(13, FontWeight.w500, c.ink2, 1.2))),
            Text(v == null ? 'Not available' : '${v.round()}%',
                style: t.custom(13, FontWeight.w600,
                    v == null ? c.grey2 : c.ink, 1.2)),
          ]),
          const SizedBox(height: 8),
          if (v != null)
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              return SizedBox(
                height: 16,
                child: Stack(clipBehavior: Clip.none, children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    height: 8,
                    child: Container(
                        decoration: BoxDecoration(
                            color: A216.barTrack,
                            borderRadius: BorderRadius.circular(4))),
                  ),
                  Positioned(
                    left: 0,
                    top: 4,
                    height: 8,
                    width: w * (v.clamp(0, 100) / 100),
                    child: Container(
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4))),
                  ),
                  if (alert != null)
                    Positioned(
                      left: w * (alert!.clamp(0, 100) / 100) - 1,
                      top: 0,
                      width: 2,
                      height: 16,
                      child: const ColoredBox(color: A216.barWarn),
                    ),
                ]),
              );
            }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------- 27. chart bars

class AdminChartBars216 extends StatelessWidget {
  final List<num> values;
  final int? highlightIndex;
  const AdminChartBars216(this.values, {super.key, this.highlightIndex});

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return CustomPaint(
      size: const Size(double.infinity, 120),
      painter: _BarsPainter(values, highlightIndex, c.blue, c.line),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<num> values;
  final int? hi;
  final Color blue;
  final Color base;
  _BarsPainter(this.values, this.hi, this.blue, this.base);

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height - 2;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY),
        Paint()..color = base..strokeWidth = 1);
    if (values.isEmpty) return;
    final max = values.fold<num>(0, (a, b) => b > a ? b : a);
    if (max <= 0) return;
    final w = size.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / max * 108;
      if (h <= 0) continue;
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH(i * w + 3, baseY - h, math.max(1, w - 6), h),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(r, Paint()..color = i == hi ? blue : A216.chartBar);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values || old.hi != hi || old.blue != blue;
}

// ------------------------------------------------------------ key / value

class AdminKeyValue216 extends StatelessWidget {
  final String k;
  final String v;
  const AdminKeyValue216(this.k, this.v, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    return SizedBox(
      height: 34,
      child: Row(children: [
        Text(k, style: t.kvKey),
        const SizedBox(width: 12),
        Expanded(
          child: Text(v,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.kvValue),
        ),
      ]),
    );
  }
}

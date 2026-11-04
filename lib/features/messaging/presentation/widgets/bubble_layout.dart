import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Bundle 182: the inside of a chat bubble, sized like WhatsApp.
///
/// Before, the text and the emoji row were wrapped in `Align`, and an `Align`
/// always grows to the widest it may be - so any bubble with text or an emoji
/// became 82% of the screen wide. Here the bubble is exactly as wide as its
/// widest part (photo, video, name, text or time):
/// * [header] (group sender name) and [body] (text) start on the start side
///   and get the full bubble width, so they line up nicely.
/// * [media] (photos / videos / files) and [footer] (time + ticks) sit on the
///   end side, as before.
/// * No media and the text fits on one line together with the time: the time
///   goes on the same line, right after the words ("hello  3:59 PM").
class BubbleContent extends MultiChildRenderObjectWidget {
  BubbleContent({
    super.key,
    this.header,
    this.body,
    this.media = const <Widget>[],
    required this.footer,
    this.inlineGap = 10,
    this.headerGap = 3,
    this.footerGap = 3,
    this.bodyAfterMedia = false,
  }) : super(children: <Widget>[
          if (header != null) header,
          if (body != null) body,
          ...media,
          footer,
        ]);

  final Widget? header;
  final Widget? body;
  final List<Widget> media;
  final Widget footer;

  /// Space between the words and the time when they share one line.
  final double inlineGap;
  final double headerGap;
  final double footerGap;

  /// Bundle 202: picture bubbles put the caption UNDER the photos (WhatsApp)
  /// and keep the caption / quote as wide as the photos.
  final bool bodyAfterMedia;

  @override
  RenderBubbleContent createRenderObject(BuildContext context) =>
      RenderBubbleContent(
        hasHeader: header != null,
        hasBody: body != null,
        inlineGap: inlineGap,
        headerGap: headerGap,
        footerGap: footerGap,
        bodyAfterMedia: bodyAfterMedia,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      );

  @override
  void updateRenderObject(
      BuildContext context, RenderBubbleContent renderObject) {
    renderObject
      ..hasHeader = header != null
      ..hasBody = body != null
      ..inlineGap = inlineGap
      ..headerGap = headerGap
      ..footerGap = footerGap
      ..bodyAfterMedia = bodyAfterMedia
      ..textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
  }
}

class BubbleContentParentData extends ContainerBoxParentData<RenderBox> {}

class RenderBubbleContent extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, BubbleContentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, BubbleContentParentData> {
  RenderBubbleContent({
    required bool hasHeader,
    required bool hasBody,
    required double inlineGap,
    required double headerGap,
    required double footerGap,
    bool bodyAfterMedia = false,
    required TextDirection textDirection,
  })  : _hasHeader = hasHeader,
        _bodyAfterMedia = bodyAfterMedia,
        _hasBody = hasBody,
        _inlineGap = inlineGap,
        _headerGap = headerGap,
        _footerGap = footerGap,
        _textDirection = textDirection;

  bool _hasHeader;
  set hasHeader(bool v) {
    if (v == _hasHeader) return;
    _hasHeader = v;
    markNeedsLayout();
  }

  bool _hasBody;
  set hasBody(bool v) {
    if (v == _hasBody) return;
    _hasBody = v;
    markNeedsLayout();
  }

  double _inlineGap;
  set inlineGap(double v) {
    if (v == _inlineGap) return;
    _inlineGap = v;
    markNeedsLayout();
  }

  double _headerGap;
  set headerGap(double v) {
    if (v == _headerGap) return;
    _headerGap = v;
    markNeedsLayout();
  }

  double _footerGap;
  set footerGap(double v) {
    if (v == _footerGap) return;
    _footerGap = v;
    markNeedsLayout();
  }

  bool _bodyAfterMedia;
  set bodyAfterMedia(bool v) {
    if (v == _bodyAfterMedia) return;
    _bodyAfterMedia = v;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection v) {
    if (v == _textDirection) return;
    _textDirection = v;
    markNeedsLayout();
  }

  /// True after the last layout put the time on the same line as the text.
  bool get timeInline => _timeInline;
  bool _timeInline = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! BubbleContentParentData) {
      child.parentData = BubbleContentParentData();
    }
  }

  List<RenderBox> get _kids {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  double _x(double width, double childWidth, {required bool end}) {
    final ltr = _textDirection == TextDirection.ltr;
    final atRight = end == ltr;
    return atRight ? width - childWidth : 0;
  }

  @override
  void performLayout() {
    final kids = _kids;
    if (kids.isEmpty) {
      size = constraints.smallest;
      return;
    }
    var i = 0;
    final header = _hasHeader ? kids[i++] : null;
    final body = _hasBody ? kids[i++] : null;
    final footer = kids.last;
    final media = kids.sublist(i, kids.length - 1);

    final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
    final loose = BoxConstraints(maxWidth: maxW);

    footer.layout(loose, parentUsesSize: true);
    final fw = footer.size.width;
    var w = fw;
    var mediaW = 0.0;
    for (final m in media) {
      m.layout(loose, parentUsesSize: true);
      mediaW = math.max(mediaW, m.size.width);
    }
    w = math.max(w, mediaW);
    // Bundle 202: caption + quote no wider than the photos.
    final capped = _bodyAfterMedia && mediaW > 0;
    final textLoose =
        capped ? BoxConstraints(maxWidth: math.max(mediaW, fw)) : loose;
    if (header != null) {
      header.layout(textLoose, parentUsesSize: true);
      w = math.max(w, header.size.width);
    }
    var inline = false;
    if (body != null) {
      if (media.isEmpty) {
        final natural = body.getMaxIntrinsicWidth(double.infinity);
        inline = natural + _inlineGap + fw <= maxW;
      }
      if (inline) {
        body.layout(BoxConstraints(maxWidth: maxW - _inlineGap - fw),
            parentUsesSize: true);
        w = math.max(w, body.size.width + _inlineGap + fw);
      } else {
        body.layout(textLoose, parentUsesSize: true);
        w = math.max(w, body.size.width);
      }
    }
    w = math.min(w, maxW);
    // Second pass: name and text get the whole bubble width so they start
    // on the start side even when a photo is wider than they are.
    if (header != null) {
      header.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
    }
    if (body != null && !inline) {
      body.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
    }
    _timeInline = inline;

    var y = 0.0;
    void place(RenderBox child, double x, double top) {
      (child.parentData! as BubbleContentParentData).offset = Offset(x, top);
    }

    if (header != null) {
      place(header, _x(w, header.size.width, end: false), y);
      y += header.size.height + _headerGap;
    }
    if (inline && body != null) {
      final rowH = math.max(body.size.height, footer.size.height);
      place(body, _x(w, body.size.width, end: false), y);
      place(footer, _x(w, fw, end: true), y + rowH - footer.size.height);
      y += rowH;
    } else {
      if (body != null && !_bodyAfterMedia) {
        place(body, _x(w, body.size.width, end: false), y);
        y += body.size.height;
      }
      for (final m in media) {
        place(m, _x(w, m.size.width, end: true), y);
        y += m.size.height;
      }
      if (body != null && _bodyAfterMedia) {
        place(body, _x(w, body.size.width, end: false), y);
        y += body.size.height;
      }
      y += _footerGap;
      place(footer, _x(w, fw, end: true), y);
      y += footer.size.height;
    }
    size = constraints.constrain(Size(w, y));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
}

/// Bundle 182: emoji chips sit on the bottom edge of the bubble (start
/// corner), half on it and half under it - like WhatsApp. They never make
/// the bubble wider.
class BubbleReactionEdge extends StatelessWidget {
  const BubbleReactionEdge({
    super.key,
    required this.bubble,
    required this.chips,
  });

  /// How far the chips hang below the bubble.
  static const double below = 16;

  /// Extra bottom padding a bubble gets when it has chips, so a chip only
  /// covers empty space.
  static const double bubblePad = 4;

  final Widget bubble;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return bubble;
    final row = <Widget>[];
    for (var k = 0; k < chips.length; k++) {
      if (k > 0) row.add(const SizedBox(width: 4));
      row.add(chips[k]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: below),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          bubble,
          PositionedDirectional(
            start: 8,
            bottom: -below,
            child: Row(
              key: const Key('bubble_reaction_edge'),
              mainAxisSize: MainAxisSize.min,
              children: row,
            ),
          ),
        ],
      ),
    );
  }
}

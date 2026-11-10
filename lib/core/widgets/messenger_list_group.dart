import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/admin_crown.dart';

/// Bundle 153 / 183: shared pieces so Chats, Calls, People, Settings and
/// Account all look the same.
///
/// * [MessengerGroupLabel]: the small grey CAPITALS title above a list
///   ("TODAY", "CONVERSATIONS", "GENERAL").
/// * [MessengerListGroup]: the Settings-style grey rounded card holding the
///   rows, with thin lines between them.
/// * [MessengerSettingsRow]: icon in a light circle + title + chevron.
/// * [MessengerCallButton]: the light-blue circle with the blue phone icon.

class MessengerGroupLabel extends StatelessWidget {
  final String text;

  /// Space above the title: 24 after a card (default), 12 at the top of a
  /// tab, 16 under the People filter chip.
  final double top;

  /// Distance of the card from the screen edge (the title sits 6 inside it).
  final double inset;

  /// Bundle 196: optional colour (the red BLOCKED part); grey when null.
  final Color? color;

  const MessengerGroupLabel(
    this.text, {
    super.key,
    this.top = 24,
    this.inset = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Bundle 183 (O1): ONE section-title style on every tab and screen -
    // small grey CAPITALS, 11 px, letter spacing 1.1 (the Settings style).
    return Padding(
      padding: EdgeInsets.fromLTRB(inset + 6, top, inset + 6, 8),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.1,
              height: 14 / 11,
              color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class MessengerListGroup extends StatelessWidget {
  final List<Widget> children;

  /// Left indent of the dividers (lines start at the text, not the avatar).
  final double dividerIndent;

  /// Distance of the card from the screen edges.
  final double inset;

  /// Bundle 255 B1: id (+ other id) of the person in row 0. While that
  /// person wears the admin crown, row 0 gets just enough top room so the
  /// card edge never cuts the crown (rows 2+ draw over the row above).
  /// Everybody else sees no change.
  final String? crownFirstId;
  final String? crownFirstOtherId;

  /// Photo radius of row 0 and the space already above that photo.
  final double crownRadius;
  final double crownAlready;

  const MessengerListGroup({
    super.key,
    required this.children,
    this.dividerIndent = 72,
    this.inset = 16,
    this.crownFirstId,
    this.crownFirstOtherId,
    this.crownRadius = 24,
    this.crownAlready = 0,
  });

  /// Bundle 255 B1: the same card with crown room for row 0.
  MessengerListGroup withCrown(String? firstId,
          {String? otherId, double radius = 24, double already = 0}) =>
      MessengerListGroup(
        key: key,
        dividerIndent: dividerIndent,
        inset: inset,
        crownFirstId: firstId,
        crownFirstOtherId: otherId,
        crownRadius: radius,
        crownAlready: already,
        children: children,
      );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          indent: dividerIndent,
          color: colors.outlineVariant.withValues(alpha: .4),
        ));
      }
      final hasCrownId = (crownFirstId ?? '').isNotEmpty ||
          (crownFirstOtherId ?? '').isNotEmpty;
      rows.add(i == 0 && hasCrownId
          ? AdminCrownRoom(
              id: crownFirstId,
              otherId: crownFirstOtherId,
              radius: crownRadius,
              already: crownAlready,
              child: children[i],
            )
          : children[i]);
    }
    // Bundle 183 (O2): ONE card style everywhere = the Settings card
    // (soft grey, thin border, corners 20). A Material (not a coloured
    // Container) so ListTile rows paint their tap ripple on it (140c).
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: .65),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .35)),
        ),
        child: Column(children: rows),
      ),
    );
  }
}

/// Bundle 183 (K5a): the one Settings-style row (icon in a light circle,
/// title, small grey line, chevron) shared by Settings and Account.
class MessengerSettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  /// Replaces the chevron (e.g. a switch).
  final Widget? trailing;

  const MessengerSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: MessengerRowIcon(icon: icon, destructive: destructive),
      title: Text(title, style: text.titleSmall),
      subtitle: Text(
        subtitle,
        // Letter spacing 0 (as in the mock) so the short lines stay on
        // one line on a 360 dp phone.
        style: text.bodySmall
            ?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            color: destructive ? colors.error : colors.onSurfaceVariant,
            size: 20,
          ),
      onTap: onTap,
    );
  }
}

/// The 40 px light circle with a 20 px icon used by [MessengerSettingsRow].
class MessengerRowIcon extends StatelessWidget {
  final IconData icon;
  final bool destructive;

  const MessengerRowIcon(
      {super.key, required this.icon, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 20,
      backgroundColor: destructive
          ? colors.errorContainer.withValues(alpha: 0.6)
          : colors.primaryContainer.withValues(alpha: 0.6),
      foregroundColor:
          destructive ? colors.onErrorContainer : colors.onPrimaryContainer,
      child: Icon(icon, size: 20),
    );
  }
}

class MessengerCallButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const MessengerCallButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Call',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.primary.withValues(alpha: 0.10),
        foregroundColor: colors.primary,
        minimumSize: const Size.square(44),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.call_outlined),
    );
  }
}

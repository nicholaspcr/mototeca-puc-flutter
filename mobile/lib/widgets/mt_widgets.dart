import 'package:flutter/material.dart';

import '../app/flavor.dart';
import '../theme.dart';

/// White card with the 1px slate border and the subtle shadow used everywhere.
class MtCard extends StatelessWidget {
  const MtCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MtSizes.cardRadius),
        border: Border.all(color: MtColors.slate200),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Labelled form field — label above, 44px control below.
class MtField extends StatelessWidget {
  const MtField({
    super.key,
    required this.label,
    this.hint,
    this.helper,
    this.controller,
    this.mono = false,
    this.obscure = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final String? hint;
  final String? helper;
  final TextEditingController? controller;
  final bool mono;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: TextStyle(fontSize: 15, fontFamily: mono ? 'monospace' : null),
          decoration: InputDecoration(hintText: hint),
        ),
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: const TextStyle(fontSize: 11, color: MtColors.slate500),
          ),
        ],
      ],
    );
  }
}

/// Pill used for the operation taxonomy and for read-only labels.
///
/// None of the three treatments uses the solid petrol fill — that belongs to
/// the primary button, and a chip wearing it reads as one. An option is an
/// outline that takes the petrol tint and a petrol rim once picked; a tag is a
/// flat neutral badge with no tap target at all.
class MtChip extends StatelessWidget {
  const MtChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
  }) : _isTag = false;

  /// Read-only label — states what was done, never responds to a tap.
  const MtChip.tag({super.key, required this.label})
    : selected = false,
      onTap = null,
      _isTag = true;

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool _isTag;

  @override
  Widget build(BuildContext context) {
    final Color bg, fg, border;
    if (_isTag) {
      bg = MtColors.slate100;
      fg = MtColors.petrol;
      border = MtColors.slate100;
    } else if (selected) {
      bg = MtColors.petrolTint;
      fg = MtColors.petrol;
      border = MtColors.petrol;
    } else {
      bg = Colors.white;
      fg = MtColors.graphite;
      border = MtColors.slate200;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected || _isTag ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// The wheel logo mark, drawn so it scales with no asset.
class MtLogo extends StatelessWidget {
  const MtLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter()),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    final center = Offset(32 * s, 32 * s);

    canvas.drawCircle(
      center,
      26 * s,
      Paint()
        ..color = MtColors.petrol
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * s,
    );

    final spoke = Paint()
      ..color = MtColors.rust
      ..strokeWidth = 6 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, Offset(52 * s, 19 * s), spoke);
    canvas.drawLine(center, Offset(12 * s, 19 * s), spoke);
    canvas.drawCircle(center, 6 * s, Paint()..color = MtColors.rust);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Small pill: the app badge in a header, a storage state, a queue state.
class MtBadge extends StatelessWidget {
  const MtBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  /// The badge naming which app a screen belongs to.
  MtBadge.flavor(AppFlavor flavor, {super.key})
    : label = flavor.badge,
      background = flavor.badgeColor,
      foreground = MtColors.slate50;

  /// Used on the screens both apps build, which belong to neither.
  const MtBadge.shared({super.key})
    : label = 'Nos dois apps',
      background = MtColors.slate500,
      foreground = MtColors.slate50;

  /// Offline is the norm, so it is the quiet colour.
  const MtBadge.offline({super.key})
    : label = 'Funciona offline',
      background = const Color(0x2422C55E),
      foreground = MtColors.successText;

  const MtBadge.online({super.key})
    : label = 'Precisa de internet',
      background = const Color(0x29EAB308),
      foreground = MtColors.warningText;

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}

/// The header of an inner screen: back arrow, title, and the app badge.
class MtAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MtAppBar({super.key, required this.title, this.badge, this.status});

  final String title;

  /// Defaults to the running app's badge; [MtBadge.shared] on a shared screen.
  final Widget? badge;

  /// Optional second line, such as where a draft is kept.
  final String? status;

  @override
  Size get preferredSize => Size.fromHeight(status == null ? 56 : 80);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (status != null) ...[
            const SizedBox(height: 4),
            MtStatusLine(status!),
          ],
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: badge ?? MtBadge.flavor(AppFlavorScope.of(context)),
        ),
      ],
    );
  }
}

/// The header of a home screen: wordmark, app badge, and one action.
class MtHomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const MtHomeHeader({
    super.key,
    required this.status,
    required this.actionLabel,
    required this.onAction,
  });

  /// Signed out and local, or who is signed in.
  final String status;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 84,
      automaticallyImplyLeading: false,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const MtLogo(),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Mototeca',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              MtBadge.flavor(AppFlavorScope.of(context)),
            ],
          ),
          const SizedBox(height: 6),
          MtStatusLine(status),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: OutlinedButton(
            key: const Key('home-acao'),
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(actionLabel),
          ),
        ),
      ],
    );
  }
}

/// Dot plus one line, stating where the data on this screen lives.
class MtStatusLine extends StatelessWidget {
  const MtStatusLine(this.text, {super.key, this.live = false});

  final String text;

  /// Green once a session backs the screen; grey while it is device-only.
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: live ? MtColors.success : MtColors.slate500,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: MtColors.petrol,
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of a home screen: what it does, what it needs, where it goes.
class MtFeatureCard extends StatelessWidget {
  const MtFeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.needsNetwork = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool needsNetwork;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MtSizes.cardRadius),
      child: MtCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: MtColors.petrolTint,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 20, color: MtColors.petrol),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MtColors.slate500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 6),
                  needsNetwork ? const MtBadge.online() : const MtBadge.offline(),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 8),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: MtColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Key/value row used by the service detail screen.
class MtDetailRow extends StatelessWidget {
  const MtDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: MtColors.slate100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: MtColors.slate500),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Muted footnote paragraph.
class MtFootnote extends StatelessWidget {
  const MtFootnote(this.text, {super.key, this.align = TextAlign.left});

  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: const TextStyle(
        fontSize: 12,
        color: MtColors.slate500,
        height: 1.5,
      ),
    );
  }
}

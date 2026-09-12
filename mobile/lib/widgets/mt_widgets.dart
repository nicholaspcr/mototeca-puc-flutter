import 'package:flutter/material.dart';

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

/// Pill used for the operation taxonomy and for status badges.
class MtChip extends StatelessWidget {
  const MtChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.background,
    this.foreground,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final bg = background ?? (selected ? MtColors.petrol : MtColors.petrolTint);
    final fg = foreground ?? (selected ? MtColors.slate50 : MtColors.rust);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
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

/// Header used on the two "home" screens: wordmark on the left, Sair on the right.
class MtHomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const MtHomeHeader({
    super.key,
    required this.subtitle,
    required this.onSignOut,
  });

  final String subtitle;
  final VoidCallback onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 84,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const MtLogo(),
              const SizedBox(width: 8),
              const Text(
                'Mototeca',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MtColors.petrol,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: OutlinedButton(
            onPressed: onSignOut,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: const Text('Sair'),
          ),
        ),
      ],
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

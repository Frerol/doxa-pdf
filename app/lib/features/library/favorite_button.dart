// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';

String favoriteLabel(AppLocalizations l10n, bool favorite) =>
    favorite ? l10n.removeFromFavorites : l10n.addToFavorites;

class FavoriteButton extends StatelessWidget {
  const FavoriteButton({
    super.key,
    required this.favorite,
    required this.onPressed,
    this.foregroundColor,
  });

  final bool favorite;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: const FavoriteStar(filled: false),
    selectedIcon: const FavoriteStar(filled: true),
    isSelected: favorite,
    color: foregroundColor,
    tooltip: favoriteLabel(AppLocalizations.of(context), favorite),
    onPressed: onPressed,
  );
}

class FavoriteStar extends StatelessWidget {
  const FavoriteStar({super.key, required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (!filled) return const Icon(LucideIcons.star);
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return CustomPaint(
      size: Size.square(size),
      painter: _FilledStarPainter(theme.color ?? const Color(0xFF000000)),
    );
  }
}

class _FilledStarPainter extends CustomPainter {
  const _FilledStarPainter(this.color);

  final Color color;

  // Lucide 1.81.0, icons/star.svg, ISC. See assets/licenses/lucide.txt.
  static final _star = Path()
    ..moveTo(11.525, 2.295)
    ..relativeArcToPoint(
      const Offset(.95, 0),
      radius: const Radius.circular(.53),
    )
    ..relativeLineTo(2.31, 4.679)
    ..relativeArcToPoint(
      const Offset(1.595, 1.16),
      radius: const Radius.circular(2.123),
      clockwise: false,
    )
    ..relativeLineTo(5.166, .756)
    ..relativeArcToPoint(
      const Offset(.294, .904),
      radius: const Radius.circular(.53),
    )
    ..relativeLineTo(-3.736, 3.638)
    ..relativeArcToPoint(
      const Offset(-.611, 1.878),
      radius: const Radius.circular(2.123),
      clockwise: false,
    )
    ..relativeLineTo(.882, 5.14)
    ..relativeArcToPoint(
      const Offset(-.771, .56),
      radius: const Radius.circular(.53),
    )
    ..relativeLineTo(-4.618, -2.428)
    ..relativeArcToPoint(
      const Offset(-1.973, 0),
      radius: const Radius.circular(2.122),
      clockwise: false,
    )
    ..lineTo(6.396, 21.01)
    ..relativeArcToPoint(
      const Offset(-.77, -.56),
      radius: const Radius.circular(.53),
    )
    ..relativeLineTo(.881, -5.139)
    ..relativeArcToPoint(
      const Offset(-.611, -1.879),
      radius: const Radius.circular(2.122),
      clockwise: false,
    )
    ..lineTo(2.16, 9.795)
    ..relativeArcToPoint(
      const Offset(.294, -.906),
      radius: const Radius.circular(.53),
    )
    ..relativeLineTo(5.165, -.755)
    ..relativeArcToPoint(
      const Offset(1.597, -1.16),
      radius: const Radius.circular(2.122),
      clockwise: false,
    )
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()..color = color;
    canvas.drawPath(_star, paint);
    canvas.drawPath(
      _star,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_FilledStarPainter oldDelegate) =>
      oldDelegate.color != color;
}

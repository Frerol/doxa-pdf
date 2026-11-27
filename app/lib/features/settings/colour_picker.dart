// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';

/// Picks an opaque page colour. By default the sample uses the chosen colour
/// on [previewOn]. Pass [previewText] to choose the sample's background instead.
Future<Color?> showColourPicker(
  BuildContext context, {
  required Color initial,
  required String title,
  Color? previewOn,
  Color? previewText,
}) => showDialog<Color>(
  context: context,
  builder: (context) => _ColourPicker(
    initial: initial,
    title: title,
    previewOn: previewOn,
    previewText: previewText,
  ),
);

class _ColourPicker extends StatefulWidget {
  const _ColourPicker({
    required this.initial,
    required this.title,
    required this.previewOn,
    required this.previewText,
  });

  final Color initial;
  final String title;
  final Color? previewOn;
  final Color? previewText;

  @override
  State<_ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<_ColourPicker> {
  static final _hexPattern = RegExp(r'^#?([0-9a-fA-F]{6})$');

  late HSVColor _colour;
  late final TextEditingController _hex;
  bool _validHex = true;

  @override
  void initState() {
    super.initState();
    _colour = HSVColor.fromColor(widget.initial.withAlpha(255));
    _hex = TextEditingController(text: _formatHex(_colour.toColor()));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  static String _formatHex(Color colour) {
    final rgb = colour.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _editHex(String input) {
    final match = _hexPattern.firstMatch(input.trim());
    setState(() {
      _validHex = match != null;
      if (match != null) {
        final rgb = int.parse(match.group(1)!, radix: 16);
        _colour = HSVColor.fromColor(Color(0xFF000000 | rgb));
      }
    });
  }

  void _pickColour(HSVColor colour) {
    final hex = _formatHex(colour.toColor());
    setState(() {
      _colour = colour;
      _validHex = true;
      _hex.value = TextEditingValue(
        text: hex,
        selection: TextSelection.collapsed(offset: hex.length),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final chosen = _colour.toColor();
    final previewBackground = widget.previewText == null
        ? widget.previewOn ?? Theme.of(context).colorScheme.surface
        : chosen;
    return AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 240,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox(
                width: 176,
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final radius = constraints.maxWidth / 2;
                      void pick(Offset position) {
                        final delta = position - Offset(radius, radius);
                        final hue =
                            (delta.direction * 180 / math.pi + 360) % 360;
                        final saturation = (delta.distance / radius).clamp(
                          0.0,
                          1.0,
                        );
                        _pickColour(
                          _colour.withHue(hue).withSaturation(saturation),
                        );
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => pick(details.localPosition),
                        onPanStart: (details) => pick(details.localPosition),
                        onPanUpdate: (details) => pick(details.localPosition),
                        child: CustomPaint(
                          key: const ValueKey('colour-wheel'),
                          painter: _WheelPainter(_colour),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.colourPickerBrightness),
            Semantics(
              label: l10n.colourPickerBrightness,
              child: Slider(
                value: _colour.value,
                onChanged: (value) => _pickColour(_colour.withValue(value)),
              ),
            ),
            TextField(
              controller: _hex,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l10n.colourPickerHex,
                hintText: '#RRGGBB',
                errorText: _validHex ? null : l10n.colourPickerInvalidHex,
              ),
              onChanged: _editHex,
            ),
            const SizedBox(height: 16),
            ColoredBox(
              color: previewBackground,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  l10n.colourPickerSample,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: widget.previewText ?? chosen),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(material.cancelButtonLabel),
        ),
        TextButton(
          onPressed: _validHex ? () => Navigator.of(context).pop(chosen) : null,
          child: Text(material.okButtonLabel),
        ),
      ],
    );
  }
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.colour);

  final HSVColor colour;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(bounds),
    );
    // The wheel shows the chosen brightness, so it matches the colour.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Color.from(
          alpha: 1 - colour.value,
          red: 0,
          green: 0,
          blue: 0,
        ),
    );

    final angle = colour.hue * math.pi / 180;
    final marker =
        center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * colour.saturation);
    canvas.drawCircle(marker, 7, Paint()..color = const Color(0xFF000000));
    canvas.drawCircle(marker, 5, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(marker, 3, Paint()..color = colour.toColor());
  }

  @override
  bool shouldRepaint(_WheelPainter oldDelegate) => oldDelegate.colour != colour;
}

// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import '../settings/settings_page.dart';
import 'color_mode.dart';
import 'reader_controller.dart';
import 'reader_geometry.dart';

/// The page layouts of the view options' grid (UX §7 "View options").
enum ViewLayout { singlePage, twoPages, coverTwoPages }

/// The grid's layout for [options]: scrolled pages are single pages.
ViewLayout viewLayoutOf(ReaderOptions options) => switch (options.mode) {
  ReaderMode.twoPages when options.coverPage => ViewLayout.coverTwoPages,
  ReaderMode.twoPages => ViewLayout.twoPages,
  _ => ViewLayout.singlePage,
};

/// How pages move: turned one by one, or scrolled vertically or
/// horizontally.
enum ViewScrolling { paged, vertical, horizontal }

/// The scrolling choice for [options].
ViewScrolling viewScrollingOf(ReaderOptions options) => switch (options.mode) {
  ReaderMode.continuous => ViewScrolling.vertical,
  ReaderMode.horizontal => ViewScrolling.horizontal,
  _ => ViewScrolling.paged,
};

/// The reader options for a [layout] and a [scrolling] choice. Two pages
/// are always turned page by page, so choosing them stops scrolling, and
/// choosing to scroll goes back to a single page.
ReaderOptions withLayout(
  ReaderOptions options,
  ViewLayout layout, {
  required ViewScrolling scrolling,
}) => switch (layout) {
  ViewLayout.singlePage => options.copyWith(
    mode: switch (scrolling) {
      ViewScrolling.paged => ReaderMode.singlePage,
      ViewScrolling.vertical => ReaderMode.continuous,
      ViewScrolling.horizontal => ReaderMode.horizontal,
    },
  ),
  ViewLayout.twoPages => options.copyWith(
    mode: ReaderMode.twoPages,
    coverPage: false,
  ),
  ViewLayout.coverTwoPages => options.copyWith(
    mode: ReaderMode.twoPages,
    coverPage: true,
  ),
};

/// Shows the view options (FR-VIEW-002, FR-VIEW-003, FR-VIEW-005): a
/// centred dialog over the dimmed reader. Changes apply live behind it;
/// it closes with OK, a tap outside or Back.
Future<void> showViewOptions(
  BuildContext context,
  ReaderController controller, {
  PageColorMode colorMode = PageColorMode.normal,
  ValueChanged<PageColorMode>? onColorMode,
  bool fullscreen = false,
  ValueChanged<bool>? onFullscreen,
  SettingsController? settings,
}) => showDialog<void>(
  context: context,
  builder: (context) => ViewOptionsDialog(
    controller: controller,
    colorMode: colorMode,
    onColorMode: onColorMode,
    fullscreen: fullscreen,
    onFullscreen: onFullscreen,
    settings: settings,
  ),
);

class ViewOptionsDialog extends StatefulWidget {
  const ViewOptionsDialog({
    super.key,
    required this.controller,
    this.colorMode = PageColorMode.normal,
    this.onColorMode,
    this.fullscreen = false,
    this.onFullscreen,
    this.settings,
  });

  final ReaderController controller;

  /// Saves layout and colour choices as defaults; without it the page
  /// colour is local to this reader ([onColorMode]).
  final SettingsController? settings;
  final PageColorMode colorMode;
  final ValueChanged<PageColorMode>? onColorMode;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreen;

  @override
  State<ViewOptionsDialog> createState() => _ViewOptionsDialogState();
}

class _ViewOptionsDialogState extends State<ViewOptionsDialog> {
  ReaderOptions get _options => widget.controller.options;
  late PageColorMode _colorMode = widget.colorMode;
  late bool _fullscreen = widget.fullscreen;

  /// Applies [options] to the reader now and saves the defaults.
  void _set(ReaderOptions options) {
    final previous = _options;
    if (options == previous) return;
    setState(() => widget.controller.setOptions(options));
    final settings = widget.settings;
    settings?.update(
      settings.value.copyWith(
        readerMode: options.mode == previous.mode ? null : options.mode,
        coverPage: options.coverPage == previous.coverPage
            ? null
            : options.coverPage,
        tapZones: options.tapZones == previous.tapZones
            ? null
            : options.tapZones,
        keepZoomOnTurn: options.keepZoomOnTurn == previous.keepZoomOnTurn
            ? null
            : options.keepZoomOnTurn,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    // About half the width in landscape, three quarters in portrait, but
    // never narrower than a phone needs.
    final width = math.min(
      size.width - 32,
      math.max(size.width * (landscape ? 0.5 : 0.75), 340.0),
    );
    final options = _options;
    final layout = viewLayoutOf(options);
    final scrolling = viewScrollingOf(options);
    final vertical = scrolling == ViewScrolling.vertical;
    final settings = widget.settings;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(l10n.viewOptions, style: theme.textTheme.titleLarge),
            ),
            // Scrolls when it does not fit (phones in landscape), with OK
            // pinned below.
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(l10n.viewLayout),
                    _LayoutGrid(
                      selected: layout,
                      onSelected: (choice) => _set(
                        withLayout(
                          options,
                          choice,
                          scrolling: choice == ViewLayout.singlePage
                              ? scrolling
                              : ViewScrolling.paged,
                        ),
                      ),
                    ),
                    _Header(l10n.viewScrolling),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: SegmentedButton<ViewScrolling>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: ViewScrolling.paged,
                            label: Text(l10n.scrollPaged),
                          ),
                          ButtonSegment(
                            value: ViewScrolling.vertical,
                            label: Text(l10n.scrollVertical),
                          ),
                          ButtonSegment(
                            value: ViewScrolling.horizontal,
                            label: Text(l10n.scrollHorizontal),
                          ),
                        ],
                        selected: {scrolling},
                        onSelectionChanged: (choice) => _set(
                          withLayout(
                            options,
                            ViewLayout.singlePage,
                            scrolling: choice.single,
                          ),
                        ),
                      ),
                    ),
                    _Header(l10n.viewPageColors),
                    if (settings != null)
                      ValueListenableBuilder<AppSettings>(
                        valueListenable: settings,
                        builder: (context, value, _) => _PageColours(
                          mode: value.colorMode,
                          onChanged: (mode) => settings.update(
                            settings.value.copyWith(colorMode: mode),
                          ),
                          onMore: () => _showColourGrid(context, settings),
                        ),
                      )
                    else if (widget.onColorMode case final onColorMode?)
                      _PageColours(
                        mode: _colorMode,
                        onChanged: (mode) {
                          setState(() => _colorMode = mode);
                          onColorMode(mode);
                        },
                      ),
                    const Divider(height: 24),
                    if (widget.onFullscreen case final onFullscreen?)
                      SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                        ),
                        title: Text(l10n.viewFullscreen),
                        subtitle: Text(l10n.viewFullscreenHint),
                        value: _fullscreen,
                        onChanged: (on) {
                          setState(() => _fullscreen = on);
                          onFullscreen(on);
                        },
                      ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(l10n.optionRightToLeft),
                      value: options.rightToLeft,
                      onChanged: vertical
                          ? null
                          : (on) => setState(
                              () => widget.controller.setOptions(
                                options.copyWith(rightToLeft: on),
                              ),
                            ),
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(l10n.optionTapZones),
                      value: options.tapZones,
                      onChanged: options.paged
                          ? (on) => _set(options.copyWith(tapZones: on))
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(l10n.optionKeepZoom),
                      value: options.keepZoomOnTurn,
                      onChanged: options.paged
                          ? (on) => _set(options.copyWith(keepZoomOnTurn: on))
                          : null,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showColourGrid(
    BuildContext context,
    SettingsController settings,
  ) => showDialog<void>(
    context: context,
    builder: (context) => _ColourGridDialog(settings: settings),
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// One selectable tile of a choice grid: an icon over its name.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(height: 8),
                Text(label, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiles in a row, all as wide and tall as the largest one's content, at
/// the start of the line; scaled down only where the line is too narrow.
class _UniformTiles extends StatelessWidget {
  const _UniformTiles({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      // A row of equal flex children is as wide as its widest child times
      // their count, so every tile takes the widest content's width.
      child: IntrinsicWidth(
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: child),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Single page, two pages and cover + two pages.
class _LayoutGrid extends StatelessWidget {
  const _LayoutGrid({required this.selected, required this.onSelected});

  final ViewLayout selected;
  final ValueChanged<ViewLayout> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiles = [
      (ViewLayout.singlePage, Icons.crop_portrait, l10n.layoutSinglePage),
      (ViewLayout.twoPages, Icons.menu_book_outlined, l10n.layoutTwoPages),
      (ViewLayout.coverTwoPages, Icons.auto_stories_outlined, l10n.layoutCover),
    ];
    return _UniformTiles(
      children: [
        for (final (layout, icon, label) in tiles)
          _ChoiceTile(
            label: label,
            selected: layout == selected,
            onTap: () => onSelected(layout),
            child: Icon(icon, size: 32),
          ),
      ],
    );
  }
}

/// Normal, night and sepia, and "More" for paper and text combinations.
class _PageColours extends StatelessWidget {
  const _PageColours({
    required this.mode,
    required this.onChanged,
    this.onMore,
  });

  final PageColorMode mode;
  final ValueChanged<PageColorMode> onChanged;

  /// Opens the combinations; hidden when custom colours cannot be saved.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final presets = [
      (PageColorMode.normal, l10n.colorNormal, Colors.white, Colors.black),
      (
        PageColorMode.night,
        l10n.colorNight,
        const Color(0xFF121212),
        const Color(0xFFE0E0E0),
      ),
      (
        PageColorMode.sepia,
        l10n.colorSepia,
        const Color(0xFFF4ECD8),
        const Color(0xFF5B4636),
      ),
    ];
    return _UniformTiles(
      children: [
        for (final (value, label, paper, ink) in presets)
          _ChoiceTile(
            label: label,
            selected: value == mode,
            onTap: () => onChanged(value),
            child: _Swatch(paper: paper, ink: ink),
          ),
        if (onMore case final onMore?)
          _ChoiceTile(
            label: l10n.colorMore,
            selected: mode == PageColorMode.custom,
            onTap: onMore,
            child: const Icon(Icons.palette_outlined, size: 32),
          ),
      ],
    );
  }
}

/// A little page in [paper] with a line of text in [ink].
class _Swatch extends StatelessWidget {
  const _Swatch({required this.paper, required this.ink});
  final Color paper;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 32,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: ExcludeSemantics(
      child: Text(
        'Aa',
        style: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Paper and text combinations, then free choice of both (FR-VIEW-016).
class _ColourGridDialog extends StatelessWidget {
  const _ColourGridDialog({required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = math.min(customBackgrounds.length, customTexts.length);
    return AlertDialog(
      title: Text(l10n.viewColourCombinations),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: ValueListenableBuilder<AppSettings>(
            valueListenable: settings,
            builder: (context, value, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (var i = 0; i < count; i++)
                      _combination(
                        context,
                        value,
                        i,
                        customBackgrounds[i],
                        customTexts[i],
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                CustomColorsEditor(settings: settings),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _combination(
    BuildContext context,
    AppSettings value,
    int index,
    Color paper,
    Color ink,
  ) {
    final l10n = AppLocalizations.of(context);
    final selected =
        value.colorMode == PageColorMode.custom &&
        value.customBackground == paper &&
        value.customText == ink;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: l10n.colourCombination(index + 1),
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => settings.update(
          value.copyWith(
            colorMode: PageColorMode.custom,
            customBackground: paper,
            customText: ink,
          ),
        ),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: paper,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          // A sample only: the tile's label names it.
          child: ExcludeSemantics(
            child: Text(
              'Aa',
              style: TextStyle(color: ink, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

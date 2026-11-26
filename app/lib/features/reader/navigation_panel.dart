// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'reader_controller.dart';

/// What the reader's side panel shows. Only sections that are built are
/// listed (UX §5): bookmarks and annotations join when they exist.
enum PanelSection { pages, outline }

/// The reader's side panel (docs/plan/05-ux-design.md §5): icons at its
/// top pick its content, page thumbnails (FR-VIEW-008) or the outline
/// (FR-VIEW-007). The reader opens and closes it with its app-bar button.
class ReaderSidePanel extends StatelessWidget {
  const ReaderSidePanel({
    super.key,
    required this.controller,
    required this.section,
    required this.onSection,
    required this.onFollow,
  });

  /// The panel's width when it sits beside the page.
  static const width = 296.0;

  final ReaderController controller;
  final PanelSection section;
  final ValueChanged<PanelSection> onSection;

  /// Called with the target of a tapped outline entry or thumbnail.
  final void Function(LinkTarget target) onFollow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = [
      (PanelSection.pages, Icons.grid_view_outlined, l10n.pagesTab),
      (PanelSection.outline, Icons.toc, l10n.outlineTab),
    ];
    final label = sections.firstWhere((s) => s.$1 == section).$3;
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                for (final (value, icon, name) in sections)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: IconButton(
                        icon: Icon(icon),
                        tooltip: name,
                        isSelected: value == section,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          backgroundColor: value == section
                              ? scheme.secondaryContainer
                              : null,
                          foregroundColor: value == section
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                        onPressed: () => onSection(value),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Semantics(
              header: true,
              child: Text(
                label.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (section) {
              PanelSection.pages => _Thumbnails(
                controller: controller,
                onFollow: onFollow,
              ),
              PanelSection.outline => _Outline(
                controller: controller,
                onFollow: onFollow,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _Outline extends StatefulWidget {
  const _Outline({required this.controller, required this.onFollow});
  final ReaderController controller;
  final void Function(LinkTarget target) onFollow;

  @override
  State<_Outline> createState() => _OutlineState();
}

class _OutlineState extends State<_Outline> {
  late final Future<List<OutlineNode>> _outline = widget.controller.engine
      .outline(widget.controller.document);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _outline,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final nodes = snapshot.data ?? const <OutlineNode>[];
        if (nodes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(l10n.outlineEmpty, textAlign: TextAlign.center),
            ),
          );
        }
        return ListView(
          children: [for (final node in nodes) _entry(context, node, 0)],
        );
      },
    );
  }

  Widget _entry(BuildContext context, OutlineNode node, int depth) {
    final target = node.target;
    final page = switch (target) {
      GoToTarget(:final destination) => widget.controller.pageLabel(
        destination.pageIndex,
      ),
      _ => null,
    };
    final padding = EdgeInsetsDirectional.only(
      start: 16.0 + depth * 16,
      end: 16,
    );
    final title = Text(
      node.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final trailing = page == null ? null : Text(page);
    void follow() {
      if (target != null) widget.onFollow(target);
    }

    if (node.children.isEmpty) {
      return ListTile(
        contentPadding: padding,
        title: title,
        trailing: trailing,
        enabled: target != null,
        onTap: follow,
      );
    }
    // A parent opens like a leaf; its arrow shows the children.
    return ExpansionTile(
      tilePadding: padding,
      title: InkWell(onTap: target == null ? null : follow, child: title),
      subtitle: trailing,
      children: [
        for (final child in node.children) _entry(context, child, depth + 1),
      ],
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({required this.controller, required this.onFollow});
  final ReaderController controller;
  final void Function(LinkTarget target) onFollow;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = controller.info.pageCount;
    return ValueListenableBuilder(
      valueListenable: controller.page,
      builder: (context, current, _) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 120,
          childAspectRatio: 0.62,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: count,
        itemBuilder: (context, page) {
          final size = controller.info.pageSize(page);
          final selected = page == current;
          return InkWell(
            onTap: () => onFollow(GoToTarget(PdfDestination(page))),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: size.width > 0 && size.height > 0
                          ? size.width / size.height
                          : 0.77,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFFFF),
                          border: Border.all(
                            color: selected ? colors.primary : colors.outline,
                            width: selected ? 3 : 1,
                          ),
                        ),
                        // Repaints as previews arrive, cell by cell. A
                        // painter, not a rebuild: the controller signals
                        // repaints during layout too (a resize when the
                        // panel opens), when widgets must not rebuild.
                        child: CustomPaint(
                          painter: _ThumbnailPainter(controller, page),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.pageLabel(page),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints page [page]'s preview once the controller has it.
class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.controller, this.page)
    : super(repaint: controller.repaint);

  final ReaderController controller;
  final int page;

  @override
  void paint(Canvas canvas, Size size) {
    final image = controller.thumbnail(page);
    if (image == null) return;
    paintImage(
      canvas: canvas,
      rect: Offset.zero & size,
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      old.controller != controller || old.page != page;
}

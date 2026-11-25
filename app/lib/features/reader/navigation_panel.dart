// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'reader_controller.dart';

/// Side panel with the outline (FR-VIEW-007) and page thumbnails
/// (FR-VIEW-008).
class NavigationPanel extends StatelessWidget {
  const NavigationPanel({
    super.key,
    required this.controller,
    required this.onFollow,
  });

  final ReaderController controller;

  /// Called with the target of a tapped outline entry or thumbnail.
  final void Function(LinkTarget target) onFollow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Drawer(
      width: 360,
      child: SafeArea(
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(text: l10n.outlineTab),
                  Tab(text: l10n.pagesTab),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _Outline(controller: controller, onFollow: onFollow),
                    _Thumbnails(controller: controller, onFollow: onFollow),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                        // Repaints as previews arrive, cell by cell.
                        child: ValueListenableBuilder(
                          valueListenable: controller.repaint,
                          builder: (context, _, _) {
                            final image = controller.thumbnail(page);
                            return image == null
                                ? const SizedBox.expand()
                                : RawImage(image: image, fit: BoxFit.fill);
                          },
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

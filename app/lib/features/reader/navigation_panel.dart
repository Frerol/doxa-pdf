// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'reader_controller.dart';

/// Contents navigation in the docked panel or on a full-screen phone route
/// (FR-VIEW-007, UX §7).
class ReaderSidePanel extends StatefulWidget {
  const ReaderSidePanel({
    super.key,
    required this.controller,
    required this.onFollow,
    this.onClose,
  });

  final ReaderController controller;
  final ValueChanged<LinkTarget> onFollow;

  /// On phones the enclosing route supplies its own back button.
  final VoidCallback? onClose;

  @override
  State<ReaderSidePanel> createState() => _ReaderSidePanelState();
}

class _ReaderSidePanelState extends State<ReaderSidePanel> {
  late final Future<List<OutlineNode>> _outline = widget.controller.engine
      .outline(widget.controller.document);
  final _expanded = <OutlineNode>{};
  bool _searching = false;
  String _query = '';

  Iterable<OutlineNode> _descendants(List<OutlineNode> nodes) sync* {
    for (final node in nodes) {
      yield node;
      yield* _descendants(node.children);
    }
  }

  Iterable<({OutlineNode node, int depth})> _visible(
    List<OutlineNode> nodes,
    int depth,
  ) sync* {
    for (final node in nodes) {
      yield (node: node, depth: depth);
      if (_expanded.contains(node)) {
        yield* _visible(node.children, depth + 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onClose case final close?)
            ListTile(
              title: Text(
                l10n.outlineTab,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                icon: const Icon(LucideIcons.x),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: close,
              ),
            ),
          Expanded(
            child: FutureBuilder(
              future: _outline,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final nodes = snapshot.data ?? const <OutlineNode>[];
                if (nodes.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.outlineEmpty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final all = _descendants(nodes).toList();
                final branches = all.where((node) => node.children.isNotEmpty);
                final allExpanded = branches.every(_expanded.contains);
                final rows = _query.isEmpty
                    ? _visible(nodes, 0).toList()
                    : [
                        for (final node in all)
                          if (node.title.toLowerCase().contains(_query))
                            (node: node, depth: 0),
                      ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(
                            _searching
                                ? LucideIcons.searchX
                                : LucideIcons.search,
                          ),
                          tooltip: _searching
                              ? MaterialLocalizations.of(context)
                                    .closeButtonTooltip
                              : l10n.outlineSearch,
                          isSelected: _searching,
                          onPressed: () => setState(() {
                            _searching = !_searching;
                            _query = '';
                          }),
                        ),
                        if (branches.isNotEmpty)
                          IconButton(
                            icon: Icon(
                              allExpanded
                                  ? LucideIcons.chevronsDownUp
                                  : LucideIcons.chevronsUpDown,
                            ),
                            tooltip: allExpanded
                                ? l10n.outlineCollapseAll
                                : l10n.outlineExpandAll,
                            onPressed: _query.isNotEmpty
                                ? null
                                : () => setState(() {
                                    if (allExpanded) {
                                      _expanded.clear();
                                    } else {
                                      _expanded.addAll(branches);
                                    }
                                  }),
                          ),
                      ],
                    ),
                    if (_searching)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: TextField(
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: l10n.outlineSearch,
                          ),
                          onChanged: (text) => setState(
                            () => _query = text.trim().toLowerCase(),
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Text(
                                l10n.outlineNoMatches,
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                return _entry(row.node, row.depth);
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _entry(OutlineNode node, int depth) {
    final target = node.target;
    final page = switch (target) {
      GoToTarget(:final destination) => widget.controller.pageLabel(
        destination.pageIndex,
      ),
      _ => null,
    };
    final expanded = _expanded.contains(node);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: EdgeInsetsDirectional.only(
          start: (depth * 16.0).clamp(0.0, constraints.maxWidth / 4),
        ),
        child: Row(
          children: [
            if (node.children.isNotEmpty && _query.isEmpty)
              IconButton(
                icon: Icon(
                  expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                ),
                tooltip: expanded
                    ? l10n.outlineCollapseEntry
                    : l10n.outlineExpandEntry,
                onPressed: () => setState(() {
                  if (expanded) {
                    _expanded.remove(node);
                  } else {
                    _expanded.add(node);
                  }
                }),
              ),
            Expanded(
              child: ListTile(
                contentPadding: const EdgeInsetsDirectional.only(
                  start: 8,
                  end: 12,
                ),
                title: Text(
                  node.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: page == null
                    ? null
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth / 4,
                        ),
                        child: Text(
                          page,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                enabled: target != null,
                onTap: target == null ? null : () => widget.onFollow(target),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

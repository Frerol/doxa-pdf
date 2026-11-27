// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';

/// The documents selected in a list, in the order they were picked
/// (FR-FILE-011). Selection mode is on while anything is selected.
final class Selection<K, V> extends ChangeNotifier {
  final _items = <K, V>{};

  bool get isActive => _items.isNotEmpty;
  int get length => _items.length;
  List<V> get values => _items.values.toList();
  bool contains(K key) => _items.containsKey(key);

  /// Selects [value] under [key], or unselects it when it already is.
  void toggle(K key, V value) {
    if (_items.remove(key) == null) _items[key] = value;
    notifyListeners();
  }

  /// Selects every one of [entries], keeping what is already selected.
  void addAll(Iterable<MapEntry<K, V>> entries) {
    _items.addEntries(entries);
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}

/// The app bar shown in place of the usual one while documents are
/// selected: how many, a way out, "Select all" and the batch [actions].
AppBar selectionAppBar(
  BuildContext context, {
  required int count,
  required VoidCallback onClear,
  required VoidCallback onSelectAll,
  required List<Widget> actions,
  PreferredSizeWidget? bottom,
}) {
  final l10n = AppLocalizations.of(context);
  return AppBar(
    leading: IconButton(
      icon: const Icon(LucideIcons.x),
      tooltip: l10n.clearSelection,
      onPressed: onClear,
    ),
    title: Text(l10n.selectedCount(count)),
    actions: [
      IconButton(
        icon: const Icon(LucideIcons.listChecks),
        tooltip: l10n.selectAll,
        onPressed: onSelectAll,
      ),
      ...actions,
    ],
    bottom: bottom,
  );
}

/// Marks [child], a list tile's leading widget, as selected.
class SelectedMark extends StatelessWidget {
  const SelectedMark({super.key, required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(LucideIcons.check, color: scheme.onPrimary),
          ),
        ),
      ],
    );
  }
}

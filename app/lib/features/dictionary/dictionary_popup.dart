// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_dict/doxa_dict.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'dictionary_import.dart';
import 'dictionary_library.dart';

/// The project page that lists Doxa's dictionary packs (FR-TEXT-012). The
/// browser downloads them; the app never uses the network (NFR-SEC-001).
const dictionariesPage =
    'https://github.com/Frerol/doxa-pdf/blob/main/docs/dictionaries.md';

/// Widths from which the lookup is a dialog instead of a bottom sheet.
const _dialogWidth = 600.0;

/// Shows what the enabled dictionaries say about [query] (FR-TEXT-008): a
/// popup on tablets, a bottom sheet on phones. Its field looks up a typed
/// word; an empty [query] opens with only the field (#121). With no
/// dictionary installed it explains how to get one (FR-TEXT-012).
Future<void> showDictionaryLookup(
  BuildContext context, {
  required String query,
  required DictionaryLibrary library,
  required DictionaryLookup lookup,
  required Future<bool> Function(String uri) openUri,
  DictionaryImporter? importer,
}) {
  final content = DictionaryLookupView(
    query: query,
    library: library,
    lookup: lookup,
    openUri: openUri,
    importer: importer,
  );
  if (MediaQuery.sizeOf(context).width >= _dialogWidth) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: content,
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: content,
    ),
  );
}

/// The lookup's contents: results grouped by dictionary in the user's
/// order, close headwords when nothing matched, or the empty state.
class DictionaryLookupView extends StatefulWidget {
  const DictionaryLookupView({
    super.key,
    required this.query,
    required this.library,
    required this.lookup,
    required this.openUri,
    this.importer,
  });

  final String query;
  final DictionaryLibrary library;
  final DictionaryLookup lookup;
  final Future<bool> Function(String uri) openUri;
  final DictionaryImporter? importer;

  @override
  State<DictionaryLookupView> createState() => _DictionaryLookupViewState();
}

class _DictionaryLookupViewState extends State<DictionaryLookupView> {
  late String _query = widget.query.trim();
  late final _field = TextEditingController(text: _query);
  Future<LookupResult>? _results;

  @override
  void initState() {
    super.initState();
    _search();
    widget.library.addListener(_onLibrary);
  }

  @override
  void dispose() {
    widget.library.removeListener(_onLibrary);
    _field.dispose();
    super.dispose();
  }

  /// A dictionary imported from the empty state answers at once.
  void _onLibrary() {
    if (mounted) setState(_search);
  }

  void _search() {
    final enabled = widget.library.enabled;
    _results = enabled.isEmpty || _query.isEmpty
        ? null
        : widget.lookup.lookup(_query, enabled);
  }

  /// Looks [word] up, from the field or a suggestion.
  void _lookUp(String word) {
    final query = word.trim();
    if (query.isEmpty) return;
    _field.text = query;
    setState(() {
      _query = query;
      _search();
    });
  }

  Future<void> _copy(List<LookupGroup> groups) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: lookupText(groups)));
    messenger.showSnackBar(SnackBar(content: Text(l10n.dictionaryCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.library.enabled.isEmpty) {
      return DictionaryEmptyState(
        openUri: widget.openUri,
        importer: widget.importer,
      );
    }
    final results = _results;
    if (results == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_header(l10n, const [])],
      );
    }
    return FutureBuilder<LookupResult>(
      future: results,
      builder: (context, snapshot) {
        final result = snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        final shownWord = result?.shownWord;
        final found = [
          for (final g in result?.groups ?? const <LookupGroup>[])
            if (g.entries.isNotEmpty) g,
        ];
        final suggestions =
            result?.suggestions.take(8).toList() ?? const <String>[];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(l10n, found),
            Flexible(
              child: switch (snapshot) {
                AsyncSnapshot(
                  connectionState: ConnectionState.done,
                  hasError: true,
                ) =>
                  _Note(l10n.dictionaryFailed),
                _ when result == null => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                _ when found.isEmpty => _NotFound(
                  query: _query,
                  suggestions: suggestions,
                  onLookUp: _lookUp,
                ),
                _ => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    if (shownWord != null)
                      Text(l10n.dictionaryShowing(shownWord)),
                    for (final group in found) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(
                          group.dictionary,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      for (final entry in group.entries) ...[
                        Text(
                          entry.headword,
                          style: theme.textTheme.titleMedium,
                        ),
                        DefinitionText(entry.definition),
                      ],
                    ],
                    if (suggestions.isNotEmpty)
                      _Suggestions(words: suggestions, onLookUp: _lookUp),
                  ],
                ),
              },
            ),
          ],
        );
      },
    );
  }

  /// The field with the looked-up word, and Copy once something is found.
  Widget _header(AppLocalizations l10n, List<LookupGroup> found) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _field,
            autofocus: _query.isEmpty,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.titleLarge,
            decoration: InputDecoration(
              hintText: l10n.dictionaryLookUpHint,
              prefixIcon: const Icon(Icons.search),
            ),
            onSubmitted: _lookUp,
          ),
        ),
        if (found.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.selectionCopy,
            onPressed: () => _copy(found),
          ),
      ],
    ),
  );
}

/// Opens the dictionary lookup with an empty field, to look up a typed word
/// (FR-TEXT-008, #121). Shows nothing when the app has no dictionaries.
class DictionaryButton extends StatelessWidget {
  const DictionaryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = DictionaryScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.menu_book_outlined),
      tooltip: AppLocalizations.of(context).dictionaryAction,
      onPressed: () => showDictionaryLookup(
        context,
        query: '',
        library: scope.library,
        lookup: scope.lookup,
        openUri: scope.openUri,
        importer: scope.importer,
      ),
    );
  }
}

/// Plain text of [groups], for Copy.
String lookupText(List<LookupGroup> groups) {
  final out = StringBuffer();
  for (final group in groups) {
    for (final entry in group.entries) {
      if (out.isNotEmpty) out.writeln();
      out.writeln('${entry.headword} (${group.dictionary})');
      for (final block in entry.definition.blocks) {
        if (block.kind == DefinitionBlockKind.listItem) out.write('• ');
        for (final span in block.spans) {
          out.write(span.text ?? '\n');
        }
        out.writeln();
      }
    }
  }
  return out.toString().trimRight();
}

/// A definition reduced to its safe subset (ADR-0009), as text.
class DefinitionText extends StatelessWidget {
  const DefinitionText(this.definition, {super.key});

  final DefinitionResult definition;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in definition.blocks)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  if (block.kind == DefinitionBlockKind.listItem)
                    const TextSpan(text: '•  '),
                  for (final span in block.spans)
                    TextSpan(
                      text: span.text ?? '\n',
                      style: TextStyle(
                        fontWeight: span.bold ? FontWeight.w600 : null,
                        fontStyle: span.italic ? FontStyle.italic : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound({
    required this.query,
    required this.suggestions,
    required this.onLookUp,
  });

  final String query;
  final List<String> suggestions;
  final ValueChanged<String> onLookUp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dictionaryNotFound(query)),
          if (suggestions.isNotEmpty)
            _Suggestions(words: suggestions, onLookUp: onLookUp),
        ],
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.words, required this.onLookUp});

  final List<String> words;
  final ValueChanged<String> onLookUp;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(AppLocalizations.of(context).dictionarySuggestions),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final word in words)
            ActionChip(label: Text(word), onPressed: () => onLookUp(word)),
        ],
      ),
    ],
  );
}

/// What to do with no dictionary installed (FR-TEXT-012, UX §9): a short
/// explanation, **Get dictionaries** and **Import file**. Settings →
/// Dictionaries supplies its own import actions.
class DictionaryEmptyState extends StatelessWidget {
  const DictionaryEmptyState({
    super.key,
    required this.openUri,
    this.importer,
    this.importActions,
  });

  final Future<bool> Function(String uri) openUri;
  final DictionaryImporter? importer;
  final Widget? importActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.dictionaryEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(l10n.dictionaryEmptyMessage, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_browser),
            label: Text(l10n.dictionaryGet),
            onPressed: () => unawaited(openUri(dictionariesPage)),
          ),
          if (importActions case final actions?) ...[
            const SizedBox(height: 8),
            actions,
          ] else if (importer case final importer?) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.file_open_outlined),
              label: Text(l10n.dictionaryImport),
              onPressed: () => unawaited(importer.pickFiles(context)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(24), child: Text(text));
}

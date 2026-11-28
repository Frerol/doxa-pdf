// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../src/doxa_theme.dart';
import 'document_actions.dart';
import 'library_home.dart' show lastReadLabel;
import 'library_repository.dart';
import 'library_thumbnails.dart';

/// The sections of the home screen; each "See all" opens its full list.
enum HomeSection { recents, favorites, folders }

/// The home screen's dashboard (docs/plan/05-ux-design.md §5): Continue
/// reading, Favorites, Folders and Recents on one screen, each with "See
/// all" for its full list.
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.library,
    required this.actions,
    required this.recents,
    required this.favorites,
    required this.folders,
    required this.thumbnails,
    required this.now,
    required this.onOpen,
    required this.onSeeAll,
    this.onAddFolder,
    this.onBrowse,
  });

  final LibraryRepository? library;
  final DocumentActions? actions;
  final Stream<List<LibraryDocument>>? recents;
  final Stream<List<LibraryDocument>>? favorites;

  /// Null where library folders are not available.
  final Stream<List<LibraryFolder>>? folders;
  final ThumbnailStore? thumbnails;
  final DateTime now;
  final ValueChanged<LibraryDocument> onOpen;
  final ValueChanged<HomeSection> onSeeAll;
  final VoidCallback? onAddFolder;
  final ValueChanged<LibraryFolder>? onBrowse;

  /// Widths from which Continue reading and Favorites sit side by side.
  static const _wide = 900.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<LibraryDocument>>(
      stream: recents,
      builder: (context, recentSnap) => StreamBuilder<List<LibraryDocument>>(
        stream: favorites,
        builder: (context, favoriteSnap) => StreamBuilder<List<LibraryFolder>>(
          stream: folders,
          builder: (context, folderSnap) {
            final recent = recentSnap.data ?? const <LibraryDocument>[];
            final favorite = favoriteSnap.data ?? const <LibraryDocument>[];
            final folderList = folderSnap.data ?? const <LibraryFolder>[];
            final waiting =
                (recents != null && !recentSnap.hasData) ||
                (favorites != null && !favoriteSnap.hasData);
            if (waiting) return const SizedBox.shrink();
            final hasFolders = folders != null;
            if (recent.isEmpty && favorite.isEmpty && folderList.isEmpty) {
              return _Empty(
                message: l10n.libraryRecentsEmpty,
                onAddFolder: hasFolders ? onAddFolder : null,
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= _wide;
                final side = constraints.maxWidth >= 600 ? 40.0 : 16.0;
                final content = constraints.maxWidth - 2 * side;
                final pair = wide && recent.isNotEmpty && favorite.isNotEmpty;
                final top = [
                  if (recent.isNotEmpty)
                    _ContinueCard(
                      document: recent.first,
                      thumbnail: thumbnails?.fileFor(recent.first.identity),
                      actions: DocumentRowActions(
                        document: recent.first,
                        library: library,
                        actions: actions,
                        showRemoveFromRecents: true,
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onPrimary,
                      ),
                      now: now,
                      onOpen: onOpen,
                    ),
                  if (favorite.isNotEmpty)
                    _FavoritesShelf(
                      // Known here, so the shelf needs no LayoutBuilder,
                      // which IntrinsicHeight below cannot measure.
                      width: pair ? (content - 22) * 100 / 235 : content,
                      documents: favorite,
                      thumbnails: thumbnails,
                      onOpen: onOpen,
                      onSeeAll: () => onSeeAll(HomeSection.favorites),
                    ),
                ];
                return ListView(
                  padding: EdgeInsets.fromLTRB(side, 8, side, 32),
                  children: [
                    if (pair)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 135, child: top[0]),
                            const SizedBox(width: 22),
                            Expanded(flex: 100, child: top[1]),
                          ],
                        ),
                      )
                    else
                      for (final (i, card) in top.indexed) ...[
                        if (i > 0) const SizedBox(height: 22),
                        card,
                      ],
                    if (hasFolders) ...[
                      const SizedBox(height: 28),
                      _SectionHeader(
                        key: const ValueKey('section-folders'),
                        title: l10n.libraryFolders,
                        action: TextButton(
                          onPressed: onAddFolder,
                          child: Text(l10n.addFolder),
                        ),
                        onSeeAll: folderList.isEmpty
                            ? null
                            : () => onSeeAll(HomeSection.folders),
                      ),
                      if (folderList.isEmpty)
                        Text(
                          l10n.libraryFoldersEmpty,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final (i, folder)
                                in folderList.take(10).indexed)
                              _FolderTile(
                                folder: folder,
                                color: brandColors[i % brandColors.length],
                                onTap: () => onBrowse?.call(folder),
                              ),
                          ],
                        ),
                    ],
                    if (recent.length > 1) ...[
                      const SizedBox(height: 28),
                      _SectionHeader(
                        key: const ValueKey('section-recents'),
                        title: l10n.libraryRecents,
                        onSeeAll: () => onSeeAll(HomeSection.recents),
                      ),
                      for (final document in recent.skip(1).take(5))
                        _RecentRow(
                          document: document,
                          actions: DocumentRowActions(
                            document: document,
                            library: library,
                            actions: actions,
                            showRemoveFromRecents: true,
                          ),
                          now: now,
                          onOpen: onOpen,
                        ),
                    ] else if (recent.length == 1) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: const ValueKey('section-recents'),
                          onPressed: () => onSeeAll(HomeSection.recents),
                          child: Text(l10n.seeAllRecents),
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// "p. 312 of 504" for [document], or nothing before its first open.
String pageLabel(AppLocalizations l10n, LibraryDocument document) =>
    document.pageCount == 0
    ? ''
    : l10n.homePage(document.state.page + 1, document.pageCount);

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.document,
    required this.actions,
    required this.thumbnail,
    required this.now,
    required this.onOpen,
  });

  final LibraryDocument document;
  final Widget actions;
  final File? thumbnail;
  final DateTime now;
  final ValueChanged<LibraryDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = document.state.page + 1;
    final details = [
      pageLabel(l10n, document),
      lastReadLabel(l10n, document.lastOpenedAt, now),
    ].where((s) => s.isNotEmpty).join(' · ');
    final percent = (document.progress * 100).floor();
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(document),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Cover(file: thumbnail, width: 120, height: 166),
                  actions,
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.continueReading.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.85),
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      document.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      document.hasUnsavedChanges
                          ? '${l10n.annotationUnsaved} · $details'
                          : details,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (document.pageCount > 0)
                          Semantics(
                            label: l10n.percentRead(percent),
                            excludeSemantics: true,
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: document.progress,
                                      strokeWidth: 6,
                                      color: scheme.onPrimary,
                                      backgroundColor: scheme.onPrimary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  Text(
                                    '$percent%',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: scheme.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: scheme.onPrimary,
                            foregroundColor: scheme.primary,
                            minimumSize: const Size(0, 48),
                          ),
                          onPressed: () => onOpen(document),
                          child: Text(
                            document.pageCount == 0
                                ? l10n.continueReading
                                : l10n.continueOnPage(page),
                          ),
                        ),
                      ],
                    ),
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

class _FavoritesShelf extends StatelessWidget {
  const _FavoritesShelf({
    required this.width,
    required this.documents,
    required this.thumbnails,
    required this.onOpen,
    required this.onSeeAll,
  });

  /// The card's width.
  final double width;
  final List<LibraryDocument> documents;
  final ThumbnailStore? thumbnails;
  final ValueChanged<LibraryDocument> onOpen;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Inside the card's padding.
    final inner = width - 32;
    final count = (inner / 110).floor().clamp(2, 6);
    final itemWidth = (inner - 12 * (count - 1)) / count;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              key: const ValueKey('section-favorites'),
              title: l10n.libraryFavorites,
              onSeeAll: onSeeAll,
              dense: true,
            ),
            Builder(
              builder: (context) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, d) in documents.take(count).indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      SizedBox(
                        width: itemWidth,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => onOpen(d),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Cover(
                                file: thumbnails?.fileFor(d.identity),
                                width: double.infinity,
                                height: 128,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                d.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.color,
    required this.onTap,
  });

  final LibraryFolder folder;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: 220,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: dark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.folder,
                    color: dark ? Color.lerp(color, Colors.white, 0.45) : color,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    folder.displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.document,
    required this.actions,
    required this.now,
    required this.onOpen,
  });

  final LibraryDocument document;
  final Widget actions;
  final DateTime now;
  final ValueChanged<LibraryDocument> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final meta = [
      pageLabel(l10n, document),
      lastReadLabel(l10n, document.lastOpenedAt, now),
    ].where((s) => s.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onOpen(document),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              // The title takes the free space and the details only what
              // they need, so the details and actions sit at the right.
              child: LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        document.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.45,
                      ),
                      child: Text(
                        document.hasUnsavedChanges
                            ? AppLocalizations.of(context).annotationUnsaved
                            : meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.action,
    this.dense = false,
  });

  final String title;
  final VoidCallback? onSeeAll;
  final Widget? action;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The actions wrap under the title when they do not fit beside it
    // (a phone at a large text size).
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 8 : 10),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Wrap(
            children: [
              ?action,
              if (onSeeAll != null)
                TextButton(onPressed: onSeeAll, child: Text(l10n.seeAll)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, this.onAddFolder});

  final String message;
  final VoidCallback? onAddFolder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/brand/doxa-glyph.png',
              width: 72,
              height: 72,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onAddFolder case final add?) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: add,
                icon: const Icon(LucideIcons.folderPlus),
                label: Text(l10n.addFolder),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A document's first page, or a placeholder before it is rendered.
class Cover extends StatelessWidget {
  const Cover({
    super.key,
    required this.file,
    required this.width,
    required this.height,
  });

  final File? file;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: width,
      height: height,
      color: scheme.surfaceContainerHighest,
      child: Icon(LucideIcons.fileText, color: scheme.outline),
    );
    final file = this.file;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: file == null
          ? placeholder
          : Image.file(
              file,
              width: width,
              height: height,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: thumbnailWidth,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import 'reader_controller.dart';
import 'thumbnail_painter.dart';

/// Full-screen page picker for the open document (FR-VIEW-008).
class ThumbnailGrid extends StatefulWidget {
  const ThumbnailGrid({super.key, required this.controller});

  final ReaderController controller;

  @override
  State<ThumbnailGrid> createState() => _ThumbnailGridState();
}

class _ThumbnailGridState extends State<ThumbnailGrid> {
  static const _spacing = 12.0;
  static const _targetCellWidth = 200.0;

  late final int _currentPage = widget.controller.currentPage;
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(AppLocalizations.of(context).thumbnails),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = math.max(
              3,
              (constraints.maxWidth / _targetCellWidth).round(),
            );
            final cellWidth =
                (constraints.maxWidth - _spacing * (columns + 1)) / columns;
            final rowHeight = math.max(0.0, cellWidth) * 1.5 + 24;
            final rowStride = rowHeight + _spacing;
            final pageCount = controller.info.pageCount;
            final rows = (pageCount / columns).ceil();
            final maxOffset = math.max(
              0.0,
              rows * rowStride + _spacing - constraints.maxHeight,
            );
            return GridView.builder(
              controller: _scroll ??= ScrollController(
                initialScrollOffset: math.min(
                  (_currentPage ~/ columns) * rowStride,
                  maxOffset,
                ),
              ),
              padding: const EdgeInsets.all(_spacing),
              scrollCacheExtent: const ScrollCacheExtent.pixels(0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: rowHeight,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
              ),
              itemCount: pageCount,
              itemBuilder: (context, page) {
                final size = controller.info.pageSize(page);
                final selected = page == _currentPage;
                return InkWell(
                  onTap: () => Navigator.of(context).pop(page),
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: size.width > 0 && size.height > 0
                                ? size.width / size.height
                                : 0.77,
                            child: ColoredBox(
                              color: const Color(0xFFFFFFFF),
                              child: CustomPaint(
                                painter: ThumbnailPainter(controller, page),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        controller.pageLabel(page),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: selected ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

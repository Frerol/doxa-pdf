// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_controller.dart';

/// A grid of page previews and labels for thumbnail navigation.
class ReaderThumbnails extends StatelessWidget {
  const ReaderThumbnails({
    super.key,
    required this.controller,
    required this.onFollow,
  });
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

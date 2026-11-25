// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' as ui;

/// LRU cache of decoded page images, bounded in bytes (ADR-0005).
///
/// The cache owns its images: it disposes them when they are evicted,
/// replaced or cleared.
final class TileCache {
  TileCache({required this.budgetBytes});

  /// The budget eviction aims for. Images that are on screen are never
  /// evicted, so the cache can exceed it while they are.
  int budgetBytes;

  final _entries = <String, _Entry>{};
  var _bytes = 0;

  int get bytes => _bytes;
  int get length => _entries.length;
  Iterable<String> get keys => _entries.keys;

  bool contains(String key) => _entries.containsKey(key);

  /// The image for [key], marked as recently used.
  ui.Image? use(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry.image;
  }

  /// The image for [key] without changing its age; for painting.
  ui.Image? peek(String key) => _entries[key]?.image;

  void put(String key, ui.Image image) {
    _remove(key);
    final bytes = image.width * image.height * 4;
    _entries[key] = _Entry(image, bytes);
    _bytes += bytes;
  }

  /// Evicts the least recently used images, except [keep], until the cache
  /// fits [budgetBytes] (or [targetBytes] when given).
  void evict({Set<String> keep = const {}, int? targetBytes}) {
    final target = targetBytes ?? budgetBytes;
    for (final key in _entries.keys.toList()) {
      if (_bytes <= target) return;
      if (keep.contains(key)) continue;
      _remove(key);
    }
  }

  /// Drops every image whose key satisfies [test].
  void removeWhere(bool Function(String key) test) {
    for (final key in _entries.keys.where(test).toList()) {
      _remove(key);
    }
  }

  void clear() => removeWhere((_) => true);

  void _remove(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return;
    _bytes -= entry.bytes;
    entry.image.dispose();
  }
}

final class _Entry {
  _Entry(this.image, this.bytes);
  final ui.Image image;
  final int bytes;
}

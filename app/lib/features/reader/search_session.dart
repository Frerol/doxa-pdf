// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:doxa_core/doxa_core.dart';
import 'package:doxa_engine/doxa_engine.dart';
import 'package:material_ui/material_ui.dart';

import 'reader_controller.dart';

/// What the search bar shows.
final class SearchStatus {
  const SearchStatus({
    this.count = 0,
    this.current = -1,
    this.searching = false,
    this.active = false,
  });

  final int count;

  /// Index of the current hit, or -1 when there is none yet.
  final int current;

  /// Pages are still being searched.
  final bool searching;

  /// A non-empty query has been started.
  final bool active;
}

/// One full-text search over the document (FR-TEXT-001, FR-TEXT-002):
/// hits stream in page by page, all hits on screen are highlighted, and
/// [next] and [previous] move between them.
///
/// The first current hit is the first one on or after the page the search
/// started from, so a search never jumps back to page 1 by itself.
final class SearchSession {
  SearchSession(this.reader);

  final ReaderController reader;
  final status = ValueNotifier(const SearchStatus());

  final _hits = <SearchHit>[];
  final _byPage = <int, List<PdfRect>>{};
  SearchQuery? _query;
  StreamSubscription<SearchHit>? _subscription;
  int _startPage = 0;
  int _current = -1;
  bool _searching = false;
  bool _active = false;
  Timer? _debounce;
  Timer? _publishTimer;

  List<SearchHit> get hits => List.unmodifiable(_hits);
  SearchHit? get currentHit =>
      _current >= 0 && _current < _hits.length ? _hits[_current] : null;

  /// Starts [query] after a short pause, so typing does not start one
  /// search per key.
  /// Whether [query] differs from the running search, or a new one is
  /// about to start.
  bool isStale(SearchQuery query) =>
      (_debounce?.isActive ?? false) ||
      _query == null ||
      _query!.text != query.text ||
      _query!.matchCase != query.matchCase ||
      _query!.wholeWord != query.wholeWord ||
      _query!.ignoreDiacritics != query.ignoreDiacritics;

  void update(
    SearchQuery query, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _debounce?.cancel();
    _debounce = Timer(delay, () => start(query));
  }

  /// Cancels any running search and starts [query] now.
  void start(SearchQuery query) {
    _debounce?.cancel();
    _cancel();
    _hits.clear();
    _byPage.clear();
    _query = query;
    _current = -1;
    _active = query.text.trim().isNotEmpty;
    _searching = _active;
    _startPage = reader.currentPage;
    _publish();
    if (!_active) return;
    _subscription = reader.engine
        .search(reader.document, query)
        .listen(_onHit, onError: (Object _) => _finish(), onDone: _finish);
  }

  void _onHit(SearchHit hit) {
    _hits.add(hit);
    (_byPage[hit.pageIndex] ??= []).addAll(hit.rects);
    if (_current < 0 && hit.pageIndex >= _startPage) {
      _current = _hits.length - 1;
      _showCurrent();
    }
    // Hits arrive in bursts: publish at most once per frame.
    _publishTimer ??= Timer(const Duration(milliseconds: 16), _publish);
  }

  void _finish() {
    _searching = false;
    _subscription = null;
    // Nothing after the start page: wrap around to the first hit.
    if (_current < 0 && _hits.isNotEmpty) {
      _current = 0;
      _showCurrent();
    }
    _publish();
  }

  void next() => _move(1);
  void previous() => _move(-1);

  void _move(int step) {
    if (_hits.isEmpty) return;
    if (_current < 0) {
      // Nothing found after the start page yet: going back means the last
      // hit before it, going forward the first one overall.
      _current = step < 0 ? _hits.length - 1 : 0;
    } else {
      _current = (_current + step) % _hits.length;
    }
    _showCurrent();
    _publish();
  }

  void _showCurrent() {
    final hit = currentHit;
    if (hit == null || hit.rects.isEmpty) return;
    unawaited(reader.reveal(hit.pageIndex, hit.rects.first));
  }

  void _publish() {
    _publishTimer?.cancel();
    _publishTimer = null;
    reader.setHighlights(HighlightLayer.searchHits, Map.of(_byPage));
    final hit = currentHit;
    reader.setHighlights(
      HighlightLayer.currentHit,
      hit == null ? const {} : {hit.pageIndex: hit.rects},
    );
    status.value = SearchStatus(
      count: _hits.length,
      current: _current,
      searching: _searching,
      active: _active,
    );
  }

  void _cancel() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  /// Stops searching and removes the highlights.
  void close() {
    _debounce?.cancel();
    _publishTimer?.cancel();
    _publishTimer = null;
    _cancel();
    _hits.clear();
    _byPage.clear();
    _query = null;
    _current = -1;
    _active = false;
    _searching = false;
    _publish();
  }

  void dispose() {
    _debounce?.cancel();
    _publishTimer?.cancel();
    _cancel();
    status.dispose();
  }
}

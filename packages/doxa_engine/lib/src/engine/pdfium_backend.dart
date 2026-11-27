// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:doxa_core/doxa_core.dart';
import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import '../api/types.dart';
import 'annotation_reader.dart';
import 'annotation_writer.dart';
import 'backend.dart';
import 'document_saver.dart';
import 'protocol.dart';

typedef _DocPtr = Pointer<fpdf_document_t__>;
typedef _PagePtr = Pointer<fpdf_page_t__>;

/// [EngineBackend] on PDFium. Must only be used from the isolate that
/// created it, because PDFium is not thread-safe.
///
/// Each document has two PDFium instances (ADR-0005): a read-only *render
/// instance*, used for rendering (with `FPDF_ANNOT`), text and navigation,
/// and an *editing instance*, loaded on demand, which is never rendered with
/// `FPDF_ANNOT` and is the only one ever saved (ADR-0008).
final class PdfiumBackend implements EngineBackend {
  PdfiumBackend(this._pdf) : _annotations = AnnotationReader(_pdf) {
    _writer = AnnotationWriter(_pdf, _annotations);
    saver = DocumentSaver(_pdf, _annotations);
    final config = calloc<FPDF_LIBRARY_CONFIG_>()..ref.version = 2;
    _pdf.FPDF_InitLibraryWithConfig(config);
    calloc.free(config);
  }

  /// Pages kept loaded per document.
  static const pageCacheSize = 8;

  /// Text layers kept per document.
  static const textCacheSize = 16;

  /// Guards against hostile outlines and link lists.
  static const maxOutlineNodes = 20000;
  static const maxOutlineDepth = 64;
  static const maxLinksPerPage = 10000;

  final PdfiumBindings _pdf;
  final AnnotationReader _annotations;
  late final AnnotationWriter _writer;

  /// Saves editing instances; tests set its `fault`.
  late final DocumentSaver saver;
  final _docs = <int, _Document>{};
  var _disposed = false;

  @override
  OpenResult open(int documentId, DocumentSource source, String? password) {
    final loaded = _load(source, password);
    if (loaded case (:final doc, :final buffer)) {
      final document = _Document(doc, buffer, source, password);
      _docs[documentId] = document;
      try {
        return DocumentOpened(DocumentHandle(documentId), _info(doc));
      } catch (_) {
        close(documentId);
        rethrow;
      }
    }
    return _openFailure(password);
  }

  /// Loads one PDFium instance, or returns null (see `FPDF_GetLastError`).
  ({_DocPtr doc, _Buffer? buffer})? _load(
    DocumentSource source,
    String? password,
  ) {
    final pass = password?.toNativeUtf8().cast<Char>() ?? nullptr.cast<Char>();
    try {
      switch (source) {
        case FileSource(:final path):
          final nativePath = path.toNativeUtf8().cast<Char>();
          final doc = _pdf.FPDF_LoadDocument(nativePath, pass);
          calloc.free(nativePath);
          return doc == nullptr ? null : (doc: doc, buffer: null);
        case MemorySource(:final bytes):
          final buffer = _Buffer.copy(bytes);
          final doc = _pdf.FPDF_LoadMemDocument64(
            buffer.pointer.cast(),
            buffer.length,
            pass,
          );
          if (doc == nullptr) {
            buffer.free();
            return null;
          }
          return (doc: doc, buffer: buffer);
      }
    } finally {
      if (pass != nullptr) calloc.free(pass);
    }
  }

  OpenResult _openFailure(String? password) =>
      switch (_pdf.FPDF_GetLastError()) {
        FPDF_ERR_PASSWORD =>
          password == null ? const PasswordRequired() : const WrongPassword(),
        FPDF_ERR_FILE => const OpenFailed(OpenFailure.file),
        FPDF_ERR_FORMAT => const OpenFailed(OpenFailure.format),
        FPDF_ERR_SECURITY => const OpenFailed(OpenFailure.security),
        final code => OpenFailed(OpenFailure.unknown, 'PDFium error $code'),
      };

  DocumentInfo _info(_DocPtr doc) {
    final count = _pdf.FPDF_GetPageCount(doc);
    final sizes = Float64List(count * 2);
    final labels = List<String?>.filled(count, null);
    final size = calloc<FS_SIZEF_>();
    try {
      for (var i = 0; i < count; i++) {
        if (_pdf.FPDF_GetPageSizeByIndexF(doc, i, size) != 0) {
          sizes[i * 2] = size.ref.width;
          sizes[i * 2 + 1] = size.ref.height;
        } else {
          // A damaged page tree entry: show a placeholder of Letter size.
          sizes[i * 2] = 612;
          sizes[i * 2 + 1] = 792;
        }
        final label = _utf16((b, l) => _pdf.FPDF_GetPageLabel(doc, i, b, l));
        labels[i] = label == null || label.isEmpty ? null : label;
      }
    } finally {
      calloc.free(size);
    }
    String? meta(String tag) {
      final nativeTag = tag.toNativeUtf8().cast<Char>();
      try {
        final value = _utf16(
          (b, l) => _pdf.FPDF_GetMetaText(doc, nativeTag, b, l),
        );
        return value == null || value.isEmpty ? null : value;
      } finally {
        calloc.free(nativeTag);
      }
    }

    return DocumentInfo(
      pageSizes: sizes,
      pageLabels: labels,
      metadata: DocumentMetadata(
        title: meta('Title'),
        author: meta('Author'),
        subject: meta('Subject'),
        keywords: meta('Keywords'),
        creator: meta('Creator'),
        producer: meta('Producer'),
        creationDate: meta('CreationDate'),
        modificationDate: meta('ModDate'),
      ),
    );
  }

  @override
  bool isOpen(int documentId) => _docs.containsKey(documentId);

  @override
  int pageCount(int documentId) =>
      _pdf.FPDF_GetPageCount(_document(documentId).render);

  @override
  void close(int documentId) {
    final document = _docs.remove(documentId);
    if (document == null) return;
    for (final page in document.pages.values) {
      _pdf.FPDF_ClosePage(page);
    }
    document.pages.clear();
    _pdf.FPDF_CloseDocument(document.render);
    final edit = document.edit;
    if (edit != null) _pdf.FPDF_CloseDocument(edit.doc);
    // PDFium reads memory documents lazily: free the copies last.
    document.buffer?.free();
    edit?.buffer?.free();
  }

  /// The editing instance of [documentId], loaded on first use. Annotation
  /// editing and saving (M2, ADR-0008) go through it, never through the
  /// render instance.
  Pointer<fpdf_document_t__> editInstance(int documentId) {
    final document = _document(documentId);
    final existing = document.edit;
    if (existing != null) return existing.doc;
    final loaded = _load(document.source, document.password);
    if (loaded == null) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'Cannot open the editing instance (PDFium error '
        '${_pdf.FPDF_GetLastError()})',
      );
    }
    document.edit = loaded;
    return loaded.doc;
  }

  /// The render instance of [documentId]; for tests.
  Pointer<fpdf_document_t__> renderInstance(int documentId) =>
      _document(documentId).render;

  @override
  PageDetails pageDetails(int documentId, int pageIndex) {
    final page = _page(documentId, pageIndex);
    final box = calloc<FS_RECTF_>();
    try {
      if (_pdf.FPDF_GetPageBoundingBox(page, box) == 0) {
        throw PdfEngineException(
          EngineErrorKind.documentError,
          'No page box on page $pageIndex',
        );
      }
      final rotation = _pdf.FPDFPage_GetRotation(page);
      return PageDetails(
        pageIndex: pageIndex,
        cropBox: PdfRect(
          box.ref.left,
          box.ref.bottom,
          box.ref.right,
          box.ref.top,
        ).normalized(),
        rotation: rotation >= 0 && rotation <= 3 ? rotation * 90 : 0,
      );
    } finally {
      calloc.free(box);
    }
  }

  @override
  List<OutlineNode> outline(int documentId) {
    final doc = _document(documentId).render;
    final budget = _Budget(maxOutlineNodes);
    return _outlineChildren(doc, nullptr, 0, <int>{}, budget);
  }

  List<OutlineNode> _outlineChildren(
    _DocPtr doc,
    Pointer<fpdf_bookmark_t__> parent,
    int depth,
    Set<int> seen,
    _Budget budget,
  ) {
    final nodes = <OutlineNode>[];
    var child = _pdf.FPDFBookmark_GetFirstChild(doc, parent);
    while (child != nullptr && budget.take()) {
      // A hostile outline can loop back on itself.
      if (!seen.add(child.address)) break;
      final bookmark = child;
      final title =
          _utf16((b, l) => _pdf.FPDFBookmark_GetTitle(bookmark, b, l)) ?? '';
      nodes.add(
        OutlineNode(
          title: title,
          target: _bookmarkTarget(doc, bookmark),
          children: depth + 1 < maxOutlineDepth
              ? _outlineChildren(doc, bookmark, depth + 1, seen, budget)
              : const [],
        ),
      );
      child = _pdf.FPDFBookmark_GetNextSibling(doc, bookmark);
    }
    return nodes;
  }

  LinkTarget? _bookmarkTarget(_DocPtr doc, Pointer<fpdf_bookmark_t__> mark) {
    final action = _pdf.FPDFBookmark_GetAction(mark);
    if (action != nullptr) return _actionTarget(doc, action);
    final dest = _pdf.FPDFBookmark_GetDest(doc, mark);
    return dest == nullptr ? null : _goTo(doc, dest);
  }

  LinkTarget? _actionTarget(_DocPtr doc, Pointer<fpdf_action_t__> action) {
    final type = _pdf.FPDFAction_GetType(action);
    switch (type) {
      case PDFACTION_GOTO:
        final dest = _pdf.FPDFAction_GetDest(doc, action);
        return dest == nullptr ? null : _goTo(doc, dest);
      case PDFACTION_URI:
        final length = _pdf.FPDFAction_GetURIPath(doc, action, nullptr, 0);
        if (length <= 1) return null;
        final buffer = calloc<Uint8>(length);
        try {
          _pdf.FPDFAction_GetURIPath(doc, action, buffer.cast(), length);
          final bytes = buffer.asTypedList(length - 1);
          return UriTarget(utf8.decode(bytes, allowMalformed: true));
        } finally {
          calloc.free(buffer);
        }
      default:
        return UnsupportedTarget(type);
    }
  }

  GoToTarget? _goTo(_DocPtr doc, Pointer<fpdf_dest_t__> dest) {
    final pageIndex = _pdf.FPDFDest_GetDestPageIndex(doc, dest);
    if (pageIndex < 0 || pageIndex >= _pdf.FPDF_GetPageCount(doc)) return null;
    final flags = calloc<Int>(3);
    final values = calloc<Float>(3);
    try {
      final ok = _pdf.FPDFDest_GetLocationInPage(
        dest,
        flags,
        flags + 1,
        flags + 2,
        values,
        values + 1,
        values + 2,
      );
      double? value(int i) =>
          ok != 0 && flags[i] != 0 && values[i].isFinite ? values[i] : null;
      final zoom = value(2);
      return GoToTarget(
        PdfDestination(
          pageIndex,
          x: value(0),
          y: value(1),
          zoom: zoom != null && zoom > 0 ? zoom : null,
        ),
      );
    } finally {
      calloc
        ..free(flags)
        ..free(values);
    }
  }

  @override
  List<PageLink> pageLinks(int documentId, int pageIndex) {
    final doc = _document(documentId).render;
    final page = _page(documentId, pageIndex);
    final start = calloc<Int>();
    final link = calloc<Pointer<fpdf_link_t__>>();
    final rect = calloc<FS_RECTF_>();
    final links = <PageLink>[];
    try {
      while (links.length < maxLinksPerPage &&
          _pdf.FPDFLink_Enumerate(page, start, link) != 0) {
        final annot = link.value;
        if (_pdf.FPDFLink_GetAnnotRect(annot, rect) == 0) continue;
        // Check the action first: FPDFLink_GetDest also resolves the /D of
        // a GoToR action, which points into another file.
        final action = _pdf.FPDFLink_GetAction(annot);
        LinkTarget? target;
        if (action != nullptr) {
          target = _actionTarget(doc, action);
        } else {
          final dest = _pdf.FPDFLink_GetDest(doc, annot);
          if (dest != nullptr) target = _goTo(doc, dest);
        }
        if (target == null) continue;
        links.add(
          PageLink(
            PdfRect(
              rect.ref.left,
              rect.ref.bottom,
              rect.ref.right,
              rect.ref.top,
            ).normalized(),
            target,
          ),
        );
      }
    } finally {
      calloc
        ..free(start)
        ..free(link)
        ..free(rect);
    }
    return links;
  }

  @override
  List<Annotation> annotations(int documentId, int pageIndex) {
    // Checks the page index against the render instance, which has the
    // same pages.
    _page(documentId, pageIndex);
    return _annotations.read(editInstance(documentId), pageIndex);
  }

  @override
  Annotation? edit(int documentId, AnnotationEdit edit) {
    final doc = editInstance(documentId);
    _document(documentId).changedPages.addAll(switch (edit) {
      AddAnnotationsEdit(:final annotations) => [
        for (final a in annotations) a.pageIndex,
      ],
      UpdateAnnotationEdit(:final annotation) => [annotation.pageIndex],
      DeleteAnnotationsEdit(:final pageIndex) => [pageIndex],
    });
    switch (edit) {
      case AddAnnotationsEdit(:final annotations):
        _writer.add(doc, annotations);
        return null;
      case UpdateAnnotationEdit(:final annotation):
        return _writer.update(doc, annotation);
      case DeleteAnnotationsEdit(:final pageIndex, :final ids):
        _writer.delete(doc, pageIndex, ids);
        return null;
    }
  }

  @override
  SaveResult save(int documentId, String path) {
    final document = _document(documentId);
    final result = saver.save(
      editInstance(documentId),
      path: path,
      password: document.password,
      changedPages: document.changedPages,
    );
    if (result is Saved) {
      document.changedPages.clear();
      final source = document.source;
      if (source is FileSource &&
          File(source.path).absolute.path == File(path).absolute.path) {
        _reopenRender(document);
      }
    }
    return result;
  }

  /// Reopens the render instance on the saved file, so it does not read
  /// the old one lazily (ADR-0005). Page text stays valid: a save changes
  /// annotations, not page content.
  void _reopenRender(_Document document) {
    final loaded = _load(document.source, document.password);
    if (loaded == null) return; // The old instance keeps serving.
    for (final page in document.pages.values) {
      _pdf.FPDF_ClosePage(page);
    }
    document.pages.clear();
    _pdf.FPDF_CloseDocument(document.render);
    document.buffer?.free();
    document
      ..render = loaded.doc
      ..buffer = loaded.buffer;
  }

  @override
  int signatureCount(int documentId) =>
      _pdf.FPDF_GetSignatureCount(_document(documentId).render)
          .clamp(0, 1 << 30);

  @override
  PageText pageText(int documentId, int pageIndex) {
    final document = _document(documentId);
    final cached = document.texts.remove(pageIndex);
    if (cached != null) return document.texts[pageIndex] = cached;

    final page = _page(documentId, pageIndex);
    final textPage = _pdf.FPDFText_LoadPage(page);
    if (textPage == nullptr) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'No text layer on page $pageIndex',
      );
    }
    final box = calloc<Double>(4);
    try {
      final count = _pdf.FPDFText_CountChars(textPage);
      final n = count < 0 ? 0 : count;
      final boxes = Float64List(n * 4);
      final text = StringBuffer();
      final unitToChar = <int>[];
      final codes = [
        for (var i = 0; i < n; i++) _pdf.FPDFText_GetUnicode(textPage, i),
      ];
      for (var i = 0; i < n; i++) {
        final code = codes[i];
        if (_isHighSurrogate(code) &&
            i + 1 < n &&
            _isLowSurrogate(codes[i + 1])) {
          // Where wchar_t is 16-bit (Windows), PDFium gives each half of a
          // surrogate pair its own char: keep both units, one per char.
          text
            ..writeCharCode(code)
            ..writeCharCode(codes[i + 1]);
          unitToChar
            ..add(i)
            ..add(i + 1);
        } else if (_isLowSurrogate(code) &&
            i > 0 &&
            _isHighSurrogate(codes[i - 1])) {
          // Written with its high half above.
        } else if (code <= 0 || code > 0x10FFFF || _isSurrogate(code)) {
          text.writeCharCode(0xFFFD);
          unitToChar.add(i);
        } else {
          text.writeCharCode(code);
          unitToChar.add(i);
          if (code > 0xFFFF) unitToChar.add(i);
        }
        // Generated chars (spaces and line breaks PDFium adds) have no box.
        if (_pdf.FPDFText_IsGenerated(textPage, i) == 1) continue;
        if (_pdf.FPDFText_GetCharBox(
              textPage,
              i,
              box,
              box + 1,
              box + 2,
              box + 3,
            ) !=
            0) {
          // GetCharBox returns left, right, bottom, top.
          boxes
            ..[i * 4] = box[0]
            ..[i * 4 + 1] = box[2]
            ..[i * 4 + 2] = box[1]
            ..[i * 4 + 3] = box[3];
        }
      }
      final result = PageText(
        pageIndex: pageIndex,
        text: text.toString(),
        charIndexOfUnit: Int32List.fromList(unitToChar),
        charBoxes: boxes,
      );
      document.texts[pageIndex] = result;
      if (document.texts.length > textCacheSize) {
        document.texts.remove(document.texts.keys.first);
      }
      return result;
    } finally {
      calloc.free(box);
      _pdf.FPDFText_ClosePage(textPage);
    }
  }

  @override
  RenderedPixels render(RenderRequest request) {
    final page = _page(request.document.id, request.pageIndex);
    final w = request.width, h = request.height;
    final pixels = malloc<Uint8>(w * h * 4);
    final matrix = calloc<FS_MATRIX_>();
    final clip = calloc<FS_RECTF_>();
    try {
      final bitmap = _pdf.FPDFBitmap_CreateEx(
        w,
        h,
        FPDFBitmap_BGRA,
        pixels.cast(),
        w * 4,
      );
      if (bitmap == nullptr) {
        throw const PdfEngineException(
          EngineErrorKind.documentError,
          'Cannot allocate the render bitmap',
        );
      }
      _pdf.FPDFBitmap_FillRect(bitmap, 0, 0, w, h, 0xFFFFFFFF);
      matrix.ref
        ..a = request.scale
        ..d = request.scale
        ..e = -request.x.toDouble()
        ..f = -request.y.toDouble();
      clip.ref
        ..right = w.toDouble()
        ..bottom = h.toDouble();
      // The render instance shows foreign annotations (ADR-0005).
      // FPDF_REVERSE_BYTE_ORDER turns PDFium's BGRA into RGBA.
      _pdf.FPDF_RenderPageBitmapWithMatrix(
        bitmap,
        page,
        matrix,
        clip,
        FPDF_ANNOT | FPDF_REVERSE_BYTE_ORDER,
      );
      _pdf.FPDFBitmap_Destroy(bitmap);
      return RenderedPixels(
        w,
        h,
        TransferableTypedData.fromList([pixels.asTypedList(w * h * 4)]),
      );
    } finally {
      malloc.free(pixels);
      calloc
        ..free(matrix)
        ..free(clip);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final id in _docs.keys.toList()) {
      close(id);
    }
    _pdf.FPDF_DestroyLibrary();
  }

  _Document _document(int documentId) {
    final document = _docs[documentId];
    if (document == null) {
      throw PdfEngineException(
        EngineErrorKind.unknownDocument,
        'Not open: $documentId',
      );
    }
    return document;
  }

  _PagePtr _page(int documentId, int pageIndex) {
    final document = _document(documentId);
    final cached = document.pages.remove(pageIndex);
    if (cached != null) return document.pages[pageIndex] = cached;
    final count = _pdf.FPDF_GetPageCount(document.render);
    if (pageIndex < 0 || pageIndex >= count) {
      throw PdfEngineException(
        EngineErrorKind.invalidPage,
        'Page $pageIndex is outside 0..${count - 1}',
      );
    }
    final page = _pdf.FPDF_LoadPage(document.render, pageIndex);
    if (page == nullptr) {
      throw PdfEngineException(
        EngineErrorKind.documentError,
        'Cannot load page $pageIndex',
      );
    }
    document.pages[pageIndex] = page;
    if (document.pages.length > pageCacheSize) {
      _pdf.FPDF_ClosePage(document.pages.remove(document.pages.keys.first)!);
    }
    return page;
  }

  /// Reads a UTF-16LE string through PDFium's two-call pattern. Returns null
  /// when PDFium has no value.
  String? _utf16(int Function(Pointer<Void> buffer, int length) read) {
    final bytes = read(nullptr, 0);
    if (bytes <= 2) return bytes == 2 ? '' : null;
    final buffer = calloc<Uint8>(bytes);
    try {
      final written = read(buffer.cast(), bytes);
      final units = (written < bytes ? written : bytes) ~/ 2 - 1;
      if (units <= 0) return '';
      return String.fromCharCodes(buffer.cast<Uint16>().asTypedList(units));
    } finally {
      calloc.free(buffer);
    }
  }
}

bool _isHighSurrogate(int code) => code >= 0xD800 && code <= 0xDBFF;
bool _isLowSurrogate(int code) => code >= 0xDC00 && code <= 0xDFFF;
bool _isSurrogate(int code) => code >= 0xD800 && code <= 0xDFFF;

final class _Document {
  _Document(this.render, this.buffer, this.source, this.password);

  _DocPtr render;
  _Buffer? buffer;
  final DocumentSource source;
  final String? password;
  ({_DocPtr doc, _Buffer? buffer})? edit;

  /// Pages whose annotations changed since the last save.
  final changedPages = <int>{};
  final pages = <int, _PagePtr>{}; // insertion order = LRU order
  final texts = <int, PageText>{};
}

/// Native copy of a memory document, alive as long as its instance.
final class _Buffer {
  _Buffer._(this.pointer, this.length);

  factory _Buffer.copy(Uint8List bytes) {
    final pointer = malloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return _Buffer._(pointer, bytes.length);
  }

  final Pointer<Uint8> pointer;
  final int length;

  void free() => malloc.free(pointer);
}

final class _Budget {
  _Budget(this._left);
  int _left;

  bool take() => _left-- > 0;
}

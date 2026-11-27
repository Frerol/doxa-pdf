// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pdfium_ffi/pdfium_ffi.dart';

import '../api/types.dart';
import 'annotation_reader.dart';

/// The steps of a save, for tests that make one of them fail.
enum SaveStep { write, verify, replace }

/// Saves an editing instance as ADR-0008 decides (FR-SAVE-002,
/// NFR-REL-003): a full save with `FPDF_SaveAsCopy` and no flags into a
/// temp file next to the target, flushed to disk, verified by reopening it,
/// then renamed over the target. A failure at any step deletes the temp
/// file and leaves the target as it was. Must only be used from the engine
/// isolate.
final class DocumentSaver {
  DocumentSaver(this._pdf, this._reader);

  final PdfiumBindings _pdf;
  final AnnotationReader _reader;

  /// Called before each step; tests throw from it to make a step fail.
  void Function(SaveStep step)? fault;

  /// Saves [edit] to [path]. [changedPages] are checked after reopening:
  /// each must hold the same annotations as [edit].
  SaveResult save(
    Pointer<fpdf_document_t__> edit, {
    required String path,
    required String? password,
    required Iterable<int> changedPages,
  }) {
    final target = File(path).absolute;
    final temp = File(
      '${target.parent.path}/.${_name(target.path)}.'
      'doxa-save-${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      final int bytes;
      try {
        fault?.call(SaveStep.write);
        bytes = _write(edit, temp);
      } on FileSystemException catch (error) {
        return SaveFailed(
          _isNoSpace(error) ? SaveFailure.noSpace : SaveFailure.writeFailed,
          error.message,
        );
      } on _WriteError catch (error) {
        return SaveFailed(SaveFailure.writeFailed, error.message);
      }

      try {
        fault?.call(SaveStep.verify);
        final problem = _verify(edit, temp.path, password, changedPages);
        if (problem != null) {
          return SaveFailed(SaveFailure.verifyFailed, problem);
        }
      } on _VerifyError catch (error) {
        return SaveFailed(SaveFailure.verifyFailed, error.message);
      } on FileSystemException catch (error) {
        return SaveFailed(SaveFailure.verifyFailed, error.message);
      }

      try {
        fault?.call(SaveStep.replace);
        temp.renameSync(target.path);
      } on FileSystemException catch (error) {
        return SaveFailed(SaveFailure.cannotReplace, error.message);
      }
      return Saved(bytes);
    } finally {
      if (temp.existsSync()) {
        try {
          temp.deleteSync();
        } on FileSystemException {
          // A stale temp file is harmless and ignored by readers.
        }
      }
    }
  }

  int _write(Pointer<fpdf_document_t__> edit, File temp) {
    final out = temp.openSync(mode: FileMode.writeOnly);
    final writer = calloc<FPDF_FILEWRITE_>();
    try {
      writer.ref
        ..version = 1
        ..WriteBlock = _writeBlock;
      _target = out;
      _error = null;
      // Flags 0: a full save, never an incremental one (ADR-0008).
      final ok = _pdf.FPDF_SaveAsCopy(edit, writer, 0) != 0;
      final error = _error;
      if (error is FileSystemException) throw error;
      if (!ok || error != null) {
        throw _WriteError('PDFium could not save the document: $error');
      }
      // Durable before the rename makes it the document.
      out.flushSync();
      return out.lengthSync();
    } finally {
      _target = null;
      calloc.free(writer);
      out.closeSync();
    }
  }

  /// Why the file at [path] is not a good copy of [edit], or null.
  String? _verify(
    Pointer<fpdf_document_t__> edit,
    String path,
    String? password,
    Iterable<int> changedPages,
  ) {
    final nativePath = path.toNativeUtf8().cast<Char>();
    final pass = password?.toNativeUtf8().cast<Char>() ?? nullptr.cast<Char>();
    final Pointer<fpdf_document_t__> copy;
    try {
      copy = _pdf.FPDF_LoadDocument(nativePath, pass);
    } finally {
      calloc.free(nativePath);
      if (pass != nullptr) calloc.free(pass);
    }
    if (copy == nullptr) {
      return 'The saved file does not open (PDFium error '
          '${_pdf.FPDF_GetLastError()})';
    }
    try {
      final pages = _pdf.FPDF_GetPageCount(edit);
      if (_pdf.FPDF_GetPageCount(copy) != pages) {
        return 'The saved file has ${_pdf.FPDF_GetPageCount(copy)} pages, '
            'not $pages';
      }
      for (final page in changedPages) {
        if (page < 0 || page >= pages) continue;
        final wanted = [for (final a in _reader.read(edit, page)) a.id];
        final saved = [for (final a in _reader.read(copy, page)) a.id];
        if (wanted.length != saved.length || !wanted.every(saved.contains)) {
          return 'Page $page of the saved file has other annotations';
        }
      }
      return null;
    } on PdfEngineException catch (error) {
      throw _VerifyError(error.message);
    } finally {
      _pdf.FPDF_CloseDocument(copy);
    }
  }

  static String _name(String path) => path.substring(path.lastIndexOf('/') + 1);

  static bool _isNoSpace(FileSystemException error) =>
      // ENOSPC on Linux and Android; ERROR_DISK_FULL on Windows.
      error.osError?.errorCode == 28 || error.osError?.errorCode == 112;
}

final class _WriteError implements Exception {
  const _WriteError(this.message);
  final String message;
}

final class _VerifyError implements Exception {
  const _VerifyError(this.message);
  final String message;
}

/// Where PDFium's output goes during one `FPDF_SaveAsCopy`. A static,
/// because the callback must be a static function; saves run one at a
/// time on the engine isolate.
RandomAccessFile? _target;
Object? _error;

int _writeBlockImpl(
  Pointer<FPDF_FILEWRITE_> self,
  Pointer<Void> data,
  int size,
) {
  try {
    _target!.writeFromSync(
      size == 0 ? Uint8List(0) : data.cast<Uint8>().asTypedList(size),
    );
    return 1;
  } on Object catch (error) {
    _error ??= error;
    return 0;
  }
}

final _writeBlock =
    Pointer.fromFunction<
      Int Function(Pointer<FPDF_FILEWRITE_>, Pointer<Void>, UnsignedLong)
    >(_writeBlockImpl, 0);

// SPDX-License-Identifier: GPL-3.0-or-later

/// Why a platform PDF save or share operation failed.
enum PdfSaveError { permissionLost, readOnly, noSpace, mismatch, failed }

class PdfSaveException implements Exception {
  const PdfSaveException(this.error, {this.recoveryPath});

  final PdfSaveError error;

  /// Cache file containing the previous document contents when write-back
  /// may have modified the URI. Keep it until recovery is complete, then
  /// delete it. Cache files may be evicted by Android.
  final String? recoveryPath;

  @override
  String toString() => 'PdfSaveException(${error.name})';
}

/// Android PDF write-back, export and sharing (FR-SAVE-002, FR-FILE-010,
/// FR-SAVE-005). Platform failures throw [PdfSaveException].
abstract interface class PdfSaves {
  /// Whether a persisted write grant covers [uri] and the provider can
  /// write it: it declares write support, or, where it does not, the
  /// document opens with "rw" (closed again without writing).
  Future<bool> canWrite(String uri);

  /// Copies the engine-verified PDF from [tempPath] to [uri] and checks
  /// the read-back SHA-256. Keep the source unchanged during the operation.
  /// The source remains caller-owned, including on failure.
  Future<void> writeBack(String uri, String tempPath);

  /// Saves and verifies [tempPath] through the system document picker.
  /// Returns the new content URI, or null on cancellation. Keep the source
  /// unchanged until this completes. The source remains caller-owned.
  Future<String?> saveCopy(String tempPath, String displayName);

  /// Opens the Android share sheet for a readable PDF content [uri].
  Future<void> share(String uri);
}

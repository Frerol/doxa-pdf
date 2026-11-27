// SPDX-License-Identifier: GPL-3.0-or-later

/// What a download the user asked for needs to know first (ADR-0010):
/// where to write it, whether it fits, and whether the network is metered.
abstract interface class DownloadConditions {
  /// The app's cache directory, where downloads are written.
  Future<String> cacheDirectory();

  /// Bytes free in [cacheDirectory], or null when unknown.
  Future<int?> freeBytes();

  /// Whether the active network is metered (mobile data, a hotspot).
  Future<bool> isMetered();
}

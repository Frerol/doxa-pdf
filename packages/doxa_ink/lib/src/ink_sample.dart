// SPDX-License-Identifier: GPL-3.0-or-later

/// Immutable digitizer sample; coordinates use the caller's stroke space.
class InkSample {
  const InkSample(this.x, this.y, this.pressure, this.timeUs);

  final double x;
  final double y;
  final double pressure;
  final int timeUs;
}

// SPDX-License-Identifier: GPL-3.0-or-later

/// Formats a PDF date in UTC, with second precision.
String formatPdfDate(DateTime date) {
  final utc = date.toUtc();
  if (utc.year < 0 || utc.year > 9999) {
    throw ArgumentError.value(date, 'date', 'PDF years must have four digits');
  }
  String pad(int n, int width) => n.toString().padLeft(width, '0');
  return 'D:${pad(utc.year, 4)}${pad(utc.month, 2)}'
      '${pad(utc.day, 2)}${pad(utc.hour, 2)}'
      '${pad(utc.minute, 2)}${pad(utc.second, 2)}Z';
}

/// Parses PDF dates; omitted components default to January 1 at midnight UTC.
DateTime? parsePdfDate(String input) {
  final match = RegExp(
    r"^(?:D:)?([0-9]{4})([0-9]{2})?([0-9]{2})?([0-9]{2})?([0-9]{2})?([0-9]{2})?(?:(Z)|([+-])([0-9]{2})(?:'([0-9]{2})'?)?)?$",
  ).firstMatch(input);
  if (match == null || match.end != input.length) return null;
  final parts = List<int>.generate(
    6,
    (i) => int.parse(match.group(i + 1) ?? (i < 3 ? '1' : '0')),
  );
  final [year, month, day, hour, minute, second] = parts;
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.year != year || date.month != month || date.day != day) return null;
  final offsetHours = int.parse(match.group(9) ?? '0');
  final offsetMinutes = int.parse(match.group(10) ?? '0');
  if (offsetHours > 23 || offsetMinutes > 59) return null;
  final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
  return match.group(8) == '-' ? date.add(offset) : date.subtract(offset);
}

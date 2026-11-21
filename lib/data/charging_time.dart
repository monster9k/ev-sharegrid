const vietnamOffset = Duration(hours: 7);

/// Vietnam calendar and clock fields, independent of the device time zone.
DateTime vietnamWallTime(DateTime instant) =>
    instant.toUtc().add(vietnamOffset);

String formatVietnamTime(DateTime instant) {
  final time = vietnamWallTime(instant);
  return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
}

String formatChargingDate(DateTime date) =>
    '${_twoDigits(date.day)}/${_twoDigits(date.month)}/${date.year}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

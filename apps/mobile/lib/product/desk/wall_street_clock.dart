/// New York Stock Exchange core-session clock.
///
/// Tokenized stocks remain available all day. This label describes the NYSE
/// regular session, including exchange holidays and scheduled 1 p.m. closes.
abstract final class WallStreetClock {
  static const _openMinutes = 9 * 60 + 30;
  static const _regularCloseMinutes = 16 * 60;
  static const _earlyCloseMinutes = 13 * 60;

  /// The last year checked date-for-date against NYSE's published calendar.
  /// Later years use the same exchange rules, but this should move forward as
  /// NYSE publishes each new rolling calendar and announces one-off closures.
  static const verifiedScheduleThroughYear = 2028;

  static String label(DateTime now) {
    final utc = now.toUtc();
    final ny = _newYorkWallClock(utc);
    final date = _dateOnly(ny);
    final minutes = ny.hour * 60 + ny.minute;
    final closeMinutes = _isEarlyClose(date)
        ? _earlyCloseMinutes
        : _regularCloseMinutes;

    if (_isTradingDay(date) &&
        minutes >= _openMinutes &&
        minutes < closeMinutes) {
      final closeUtc = _newYorkWallToUtc(date, closeMinutes);
      return 'Stocks trade here 24/7. Wall Street closes in ${_duration(closeUtc.difference(utc))}.';
    }

    final nextOpenUtc = _nextOpenUtc(ny);
    return 'Stocks trade here 24/7. Wall Street opens in ${_duration(nextOpenUtc.difference(utc))}.';
  }

  /// Produces a UTC-backed value whose fields represent the New York wall
  /// clock. UTC backing keeps all date arithmetic independent of device locale.
  static DateTime _newYorkWallClock(DateTime utc) {
    final offset = _inUsDaylightTime(utc) ? -4 : -5;
    final shifted = utc.add(Duration(hours: offset));
    return DateTime.utc(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  static DateTime _newYorkWallToUtc(DateTime date, int minutes) {
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    // Core-session boundaries never fall inside the 2 a.m. DST transition.
    final daylight = _dateUsesDaylightTime(date);
    return DateTime.utc(
      date.year,
      date.month,
      date.day,
      hour + (daylight ? 4 : 5),
      minute,
    );
  }

  static bool _inUsDaylightTime(DateTime utc) {
    final year = utc.year;
    // Since 2007, New York changes at 07:00 UTC on the second Sunday in March
    // and at 06:00 UTC on the first Sunday in November.
    final start = DateTime.utc(
      year,
      DateTime.march,
      _nthWeekdayOfMonth(year, DateTime.march, DateTime.sunday, 2).day,
      7,
    );
    final end = DateTime.utc(
      year,
      DateTime.november,
      _nthWeekdayOfMonth(year, DateTime.november, DateTime.sunday, 1).day,
      6,
    );
    return !utc.isBefore(start) && utc.isBefore(end);
  }

  static bool _dateUsesDaylightTime(DateTime date) {
    final start = _nthWeekdayOfMonth(
      date.year,
      DateTime.march,
      DateTime.sunday,
      2,
    );
    final end = _nthWeekdayOfMonth(
      date.year,
      DateTime.november,
      DateTime.sunday,
      1,
    );
    return !date.isBefore(start) && date.isBefore(end);
  }

  static DateTime _nextOpenUtc(DateTime ny) {
    var date = _dateOnly(ny);
    final openToday = DateTime.utc(date.year, date.month, date.day, 9, 30);
    if (_isTradingDay(date) && ny.isBefore(openToday)) {
      return _newYorkWallToUtc(date, _openMinutes);
    }

    do {
      date = date.add(const Duration(days: 1));
    } while (!_isTradingDay(date));
    return _newYorkWallToUtc(date, _openMinutes);
  }

  static bool _isTradingDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    return !_exchangeHolidays(date.year).contains(_dateKey(date));
  }

  static bool _isEarlyClose(DateTime date) {
    if (!_isTradingDay(date)) return false;

    // NYSE's published 2025-2028 calendars schedule 1 p.m. closes on a
    // trading-day July 3, the day after Thanksgiving, and a trading-day
    // Christmas Eve. These recurring rules also generate later years.
    if (date.month == DateTime.july && date.day == 3) return true;
    if (date.month == DateTime.december && date.day == 24) return true;

    final thanksgiving = _nthWeekdayOfMonth(
      date.year,
      DateTime.november,
      DateTime.thursday,
      4,
    );
    return _sameDate(date, thanksgiving.add(const Duration(days: 1)));
  }

  static Set<int> _exchangeHolidays(int year) {
    final holidays = <int>{};

    // NYSE does not observe a Saturday New Year's Day on the preceding
    // Friday because that Friday closes the prior accounting year.
    _addObserved(
      holidays,
      DateTime.utc(year, DateTime.january, 1),
      observeSaturday: false,
    );
    holidays.add(
      _dateKey(_nthWeekdayOfMonth(year, DateTime.january, DateTime.monday, 3)),
    );
    holidays.add(
      _dateKey(_nthWeekdayOfMonth(year, DateTime.february, DateTime.monday, 3)),
    );
    holidays.add(
      _dateKey(_easterSunday(year).subtract(const Duration(days: 2))),
    );
    holidays.add(
      _dateKey(_lastWeekdayOfMonth(year, DateTime.may, DateTime.monday)),
    );

    // Juneteenth became an NYSE holiday in 2022.
    if (year >= 2022) {
      _addObserved(holidays, DateTime.utc(year, DateTime.june, 19));
    }
    _addObserved(holidays, DateTime.utc(year, DateTime.july, 4));
    holidays.add(
      _dateKey(
        _nthWeekdayOfMonth(year, DateTime.september, DateTime.monday, 1),
      ),
    );
    holidays.add(
      _dateKey(
        _nthWeekdayOfMonth(year, DateTime.november, DateTime.thursday, 4),
      ),
    );
    _addObserved(holidays, DateTime.utc(year, DateTime.december, 25));

    // Published one-off closures cannot be inferred from recurring rules.
    // Keep them explicit so the source stays auditable.
    if (year == 2025) holidays.add(20250109);

    return holidays;
  }

  static void _addObserved(
    Set<int> holidays,
    DateTime holiday, {
    bool observeSaturday = true,
  }) {
    holidays.add(_dateKey(holiday));
    if (holiday.weekday == DateTime.saturday && observeSaturday) {
      holidays.add(_dateKey(holiday.subtract(const Duration(days: 1))));
    } else if (holiday.weekday == DateTime.sunday) {
      holidays.add(_dateKey(holiday.add(const Duration(days: 1))));
    }
  }

  static DateTime _nthWeekdayOfMonth(
    int year,
    int month,
    int weekday,
    int occurrence,
  ) {
    final first = DateTime.utc(year, month);
    final firstMatch = 1 + (weekday - first.weekday + 7) % 7;
    return DateTime.utc(year, month, firstMatch + (occurrence - 1) * 7);
  }

  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final last = DateTime.utc(
      year,
      month + 1,
    ).subtract(const Duration(days: 1));
    return last.subtract(Duration(days: (last.weekday - weekday + 7) % 7));
  }

  static DateTime _easterSunday(int year) {
    // Gregorian computus, valid for the modern NYSE calendar range.
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = (h + l - 7 * m + 114) % 31 + 1;
    return DateTime.utc(year, month, day);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);

  static int _dateKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  static String _duration(Duration duration) {
    final minutes = duration.inSeconds <= 0
        ? 1
        : (duration.inSeconds + Duration.secondsPerMinute - 1) ~/
              Duration.secondsPerMinute;
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    if (hours < 24) {
      return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
    }
    final days = hours ~/ 24;
    final left = hours % 24;
    return left == 0 ? '${days}d' : '${days}d ${left}h';
  }
}

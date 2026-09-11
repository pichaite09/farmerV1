/// Date helpers for the Thai UI and Gregorian API contract.
class ThaiDate {
  ThaiDate._();

  static const _months = <String>[
    'มกราคม',
    'กุมภาพันธ์',
    'มีนาคม',
    'เมษายน',
    'พฤษภาคม',
    'มิถุนายน',
    'กรกฎาคม',
    'สิงหาคม',
    'กันยายน',
    'ตุลาคม',
    'พฤศจิกายน',
    'ธันวาคม',
  ];
  static const _weekdays = <String>[
    'จันทร์',
    'อังคาร',
    'พุธ',
    'พฤหัสบดี',
    'ศุกร์',
    'เสาร์',
    'อาทิตย์',
  ];

  /// Displays a date using Thai names and Buddhist Era year.
  static String format(DateTime value, {bool includeWeekday = false}) {
    final date = '${value.day} ${_months[value.month - 1]} ${value.year + 543}';
    if (!includeWeekday) return date;
    final weekday = _weekdays[value.weekday - 1];
    return 'วัน$weekday $date';
  }

  /// Returns the Gregorian date-only value expected by API endpoints.
  static String toIsoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Parses either a Gregorian ISO date or a Thai Buddhist Era date (dd/MM/yyyy).
  static DateTime parse(String input) {
    final value = input.trim();
    final thai = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value);
    if (thai != null) {
      return _validated(
        int.parse(thai.group(3)!) - 543,
        int.parse(thai.group(2)!),
        int.parse(thai.group(1)!),
        value,
      );
    }

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (iso != null) {
      return _validated(
        int.parse(iso.group(1)!),
        int.parse(iso.group(2)!),
        int.parse(iso.group(3)!),
        value,
      );
    }
    throw FormatException('รูปแบบวันที่ไม่ถูกต้อง', input);
  }

  static DateTime _validated(int year, int month, int day, String input) {
    final result = DateTime(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      throw FormatException('วันที่ไม่ถูกต้อง', input);
    }
    return result;
  }
}

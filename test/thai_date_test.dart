import 'package:flutter_test/flutter_test.dart';
import 'package:farmer/utils/thai_date.dart';

void main() {
  final date = DateTime(2025, 1, 5);

  test(
    'formats Thai dates with Buddhist Era while preserving Thai month names',
    () {
      expect(ThaiDate.format(date), '5 มกราคม 2568');
      expect(ThaiDate.format(date, includeWeekday: true), contains('อาทิตย์'));
    },
  );

  test('serializes dates as Gregorian ISO wire values', () {
    expect(ThaiDate.toIsoDate(date), '2025-01-05');
    expect(ThaiDate.toIsoDate(DateTime(2025, 1, 5, 14, 30)), '2025-01-05');
  });

  test('parses ISO wire values and Thai Buddhist Era input', () {
    expect(ThaiDate.parse('2025-01-05'), date);
    expect(ThaiDate.parse('05/01/2568'), date);
  });

  test('rejects malformed or impossible dates', () {
    expect(() => ThaiDate.parse('not-a-date'), throwsFormatException);
    expect(() => ThaiDate.parse('31/02/2568'), throwsFormatException);
  });
}

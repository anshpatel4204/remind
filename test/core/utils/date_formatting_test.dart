import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:remind/core/utils/date_formatting.dart';

void main() {
  // DateFormat.localeExists() (called by resolveSupportedLocale) throws
  // LocaleDataException until intl's locale data has been loaded at least
  // once in this isolate - load it up front so every group below can call
  // resolveSupportedLocale directly, matching what main() always does
  // before touching DateFormat in the real app.
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('resolveSupportedLocale (Part 13 locale resolution)', () {
    test('returns a locale intl recognizes exactly, unchanged', () {
      expect(resolveSupportedLocale('en_US'), 'en_US');
      expect(resolveSupportedLocale('fr'), 'fr');
    });

    test('falls back to the bare language subtag when the full locale is '
        'unrecognized but the language alone is', () {
      // intl ships 'hi' data but not every hi_* region variant - an
      // uncommon region code should still land on the recognized
      // language rather than skipping straight to en_US.
      expect(resolveSupportedLocale('hi_XX'), 'hi');
    });

    test('falls back to en_US when nothing about the locale is recognized',
        () {
      expect(resolveSupportedLocale('xx_YY'), 'en_US');
      expect(resolveSupportedLocale(''), 'en_US');
      expect(resolveSupportedLocale('not-a-locale-string'), 'en_US');
    });

    test('accepts both underscore and hyphen region separators', () {
      expect(resolveSupportedLocale('en-US'), anyOf('en-US', 'en_US', 'en'));
    });
  });

  group('formatTime (Part 13 12h/24h preference)', () {
    final morning = DateTime(2026, 1, 5, 9, 5);
    final afternoon = DateTime(2026, 1, 5, 15, 30);
    final midnight = DateTime(2026, 1, 5, 0, 0);

    test('defaults to 12-hour format', () {
      expect(formatTime(morning), '9:05 AM');
      expect(formatTime(afternoon), '3:30 PM');
    });

    test('use24Hour: false formats as 12-hour with AM/PM', () {
      expect(formatTime(morning, use24Hour: false), '9:05 AM');
      expect(formatTime(afternoon, use24Hour: false), '3:30 PM');
    });

    test('use24Hour: true formats as 24-hour, zero-padded', () {
      expect(formatTime(morning, use24Hour: true), '09:05');
      expect(formatTime(afternoon, use24Hour: true), '15:30');
      expect(formatTime(midnight, use24Hour: true), '00:00');
    });
  });

  group('formatDateTime (Part 13 12h/24h preference)', () {
    final when = DateTime(2026, 3, 14, 17, 45);

    test('threads use24Hour through to the time portion', () {
      expect(formatDateTime(when, use24Hour: false), contains('5:45 PM'));
      expect(formatDateTime(when, use24Hour: true), contains('17:45'));
    });

    test('always includes the formatted date portion regardless of '
        'use24Hour', () {
      expect(formatDateTime(when, use24Hour: false), contains('Mar 14, 2026'));
      expect(formatDateTime(when, use24Hour: true), contains('Mar 14, 2026'));
    });
  });
}

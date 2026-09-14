import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
final DateFormat _time12Format = DateFormat('h:mm a');
final DateFormat _time24Format = DateFormat('HH:mm');

/// Sets [Intl.defaultLocale] to the device's own locale and loads that
/// locale's date/time symbol data (month names, AM/PM strings, etc.), so
/// every [DateFormat] built after this call - including the module-level
/// ones above - actually reflects the device's locale instead of always
/// falling back to `intl`'s built-in `en_US` default. Called once from
/// `main()`, before `runApp()`.
///
/// [rawLocale] is normally `PlatformDispatcher.instance.locale.toString()`
/// (a parameter here, rather than reading `PlatformDispatcher` directly,
/// purely so this is unit-testable with an arbitrary locale string
/// without needing a real platform binding). Falls back to `en_US` - and
/// is guaranteed never to throw - if [rawLocale] isn't one `intl` ships
/// data for (an uncommon device locale, or a malformed string): a user
/// with an unrecognized locale still gets a fully working, just
/// non-locale-matched, app rather than a startup crash.
Future<String> initializeAppLocale(String rawLocale) async {
  // DateFormat.localeExists() (used by resolveSupportedLocale below) throws
  // LocaleDataException rather than returning false if no locale data has
  // ever been loaded yet - intl's non-web/VM data source isn't paginated
  // per locale, so a single bare call here loads every locale's data at
  // once and makes every later localeExists() check in this file safe.
  await initializeDateFormatting();
  final resolved = resolveSupportedLocale(rawLocale);
  await initializeDateFormatting(resolved);
  Intl.defaultLocale = resolved;
  return resolved;
}

/// Pure resolution logic behind [initializeAppLocale], split out so it's
/// testable without touching `intl`'s actual locale-data loading (which
/// needs async initialization) or a platform binding. Returns
/// [rawLocale] itself when `intl` recognizes it exactly; otherwise falls
/// back to just the language subtag (e.g. `"hi_IN"` -> `"hi"`) when that
/// alone is recognized; otherwise falls back to `"en_US"`.
String resolveSupportedLocale(String rawLocale) {
  if (DateFormat.localeExists(rawLocale)) return rawLocale;
  final language = rawLocale.split(RegExp('[_-]')).first;
  if (DateFormat.localeExists(language)) return language;
  return 'en_US';
}

String formatDate(DateTime date) => _dateFormat.format(date);

String formatTime(DateTime time, {bool use24Hour = false}) =>
    (use24Hour ? _time24Format : _time12Format).format(time);

String formatDateTime(DateTime dateTime, {bool use24Hour = false}) =>
    '${formatDate(dateTime)} • ${formatTime(dateTime, use24Hour: use24Hour)}';

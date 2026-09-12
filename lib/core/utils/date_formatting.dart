import 'package:intl/intl.dart';

final DateFormat _dateFormat = DateFormat('MMM d, yyyy');
final DateFormat _timeFormat = DateFormat('h:mm a');
final DateFormat _dateTimeFormat = DateFormat('MMM d, yyyy • h:mm a');

String formatDate(DateTime date) => _dateFormat.format(date);

String formatTime(DateTime time) => _timeFormat.format(time);

String formatDateTime(DateTime dateTime) => _dateTimeFormat.format(dateTime);

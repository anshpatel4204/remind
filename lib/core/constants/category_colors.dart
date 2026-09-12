import 'package:flutter/material.dart';

/// Presentation-only default colors for the 7 seeded categories, used
/// only when a category has no explicit `color` stored in the database.
/// This is purely a UI concern - it does not touch the Part 2 schema or
/// seed data, which intentionally store no color for default categories.
const Map<String, Color> kDefaultCategoryColors = {
  'Work': Color(0xFF5338FC),
  'Study': Color(0xFF2E86AB),
  'Personal': Color(0xFF06A77D),
  'Finance': Color(0xFFC77DFF),
  'Shopping': Color(0xFFF77F00),
  'Health': Color(0xFFE63946),
  'Other': Color(0xFF6C757D),
};

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

/// The palette offered when picking a category's color. Starts with the
/// hex equivalents of [kDefaultCategoryColors] (so custom categories can
/// look at home next to the defaults), then a broader spread of hues and a
/// couple of neutrals, giving 24 options in total.
const List<String> kCategoryColorSwatches = [
  // Matches the 7 default categories' colors, in the same order.
  '#5338FC',
  '#2E86AB',
  '#06A77D',
  '#C77DFF',
  '#F77F00',
  '#E63946',
  '#6C757D',
  // Additional hues, for custom categories.
  '#118AB2',
  '#3A86FF',
  '#4361EE',
  '#7209B7',
  '#9B5DE5',
  '#8338EC',
  '#F15BB5',
  '#EF476F',
  '#FB5607',
  '#E76F51',
  '#FFD60A',
  '#FFCA3A',
  '#06D6A0',
  '#00BBF9',
  '#00F5D4',
  '#A0522D',
  '#495057',
];

/// Presentation-only default icons for the 7 seeded categories, used only
/// as a fallback when a category has no meaningful `iconName` stored (the
/// schema has the column, but nothing currently populates it) - purely a
/// UI concern, same spirit as [kDefaultCategoryColors].
const Map<String, IconData> kDefaultCategoryIcons = {
  'Work': Icons.work_outline,
  'Study': Icons.menu_book_outlined,
  'Personal': Icons.home_outlined,
  'Finance': Icons.account_balance_wallet_outlined,
  'Shopping': Icons.shopping_cart_outlined,
  'Health': Icons.favorite_outline,
  'Other': Icons.chat_bubble_outline,
};

/// Fallback icon for a custom category that doesn't match any of the
/// defaults above.
const IconData kFallbackCategoryIcon = Icons.label_outline;

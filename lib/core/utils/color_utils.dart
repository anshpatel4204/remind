import 'package:flutter/material.dart';

/// Parses a `#RRGGBB` or `#AARRGGBB` hex string (as stored on a category's
/// or tag's `color` field) into a [Color]. Returns null for a
/// null/empty/unparseable input so callers can fall back to a theme color.
Color? colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  final parsed = int.tryParse(value, radix: 16);
  return parsed == null ? null : Color(parsed);
}

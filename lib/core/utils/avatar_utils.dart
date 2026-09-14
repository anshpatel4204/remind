import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Derives a "generated initials avatar" (Part 13's profile picture,
/// deliberately not a real photo - see `ProfileEditScreen`'s doc comment
/// for why) purely from a display name: no state to store beyond the
/// name itself, so there's nothing extra to keep in sync or migrate.
class AvatarUtils {
  AvatarUtils._();

  /// A small, fixed palette of REmind's own brand colors, so a generated
  /// avatar always looks "on brand" rather than a clashing random hue.
  static const List<Color> _palette = [
    AppColors.brandPurple,
    AppColors.brandBlue,
    AppColors.brandCyan,
    AppColors.brandNavy,
    AppColors.brandPurpleLight,
    AppColors.success,
  ];

  /// One or two initials from [name] (e.g. "Ansh Patel" -> "AP", "ansh" ->
  /// "A"). Falls back to a single generic person glyph's worth of "?" for
  /// an empty/unset name, so a caller never has to special-case "no name"
  /// separately from "name with no letters in it".
  static String initialsFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final first = parts.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 ? parts.last[0] : '';
    final initials = (first + last).toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }

  /// A deterministic color from [_palette] for [name], so the same name
  /// always renders the same avatar color across app restarts (nothing
  /// about the color is stored - it's recomputed from the name every
  /// time). An unset name always gets the first palette color, matching
  /// [initialsFor]'s "?" fallback.
  static Color colorFor(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return _palette.first;
    final index = trimmed.toLowerCase().hashCode.abs() % _palette.length;
    return _palette[index];
  }
}

/// A ready-to-place circular generated-initials avatar for [name], sized
/// by [radius]. Used in Settings' Profile row, the Profile edit screen,
/// and the About/onboarding screens - kept as one widget rather than
/// repeating the `CircleAvatar` + text-style boilerplate at each site.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.radius = 24});

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AvatarUtils.colorFor(name),
      child: Text(
        AvatarUtils.initialsFor(name),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: radius * 0.7,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../data/models/enums.dart';
import '../utils/task_status_calculator.dart';

/// REmind's single source of truth for color - every screen and widget
/// should pull brand/priority/status colors from here rather than
/// declaring its own hex literal.
///
/// These exact values come from the REmind UI reference (the master
/// visual design lock) rather than being algorithmically derived, so the
/// app matches the reference precisely instead of approximating it via
/// `ColorScheme.fromSeed`. [AppTheme] seeds Material's tonal palette from
/// [brandPurple]/[darkPrimary] for the color roles the reference doesn't
/// pin down (container/elevation tints), then overrides every role the
/// reference does specify - see [AppTheme] for how light vs. dark mode
/// differ deliberately rather than one being an inversion of the other.
class AppColors {
  AppColors._();

  // Brand - the REmind blue-purple identity. brandPurple is the primary
  // interactive color in light mode (buttons, FAB, selected nav item);
  // brandBlue/brandCyan are supporting accents (gradients, secondary
  // actions); brandNavy is the deep tone used for splash/onboarding.
  static const Color brandNavy = Color(0xFF081957);
  static const Color brandBlue = Color(0xFF2679F0);
  static const Color brandCyan = Color(0xFF33ABF7);
  static const Color brandPurple = Color(0xFF534BF5);
  static const Color brandPurpleLight = Color(0xFF706CEF);

  // Light-mode surfaces & text.
  static const Color background = Color(0xFFFCFCFD);
  static const Color surface = Color(0xFFF3F5FB);
  static const Color textPrimary = Color(0xFF0C1425);
  static const Color textSecondary = Color(0xFF616875);
  static const Color border = Color(0xFFE0E3F3);

  // Dark-mode surfaces & text. Deliberately chosen, not a simple
  // inversion of the light values: the background/surface are the exact
  // reference darks, and the text/border tones are picked for contrast
  // and readability against them rather than mechanically flipped.
  static const Color darkBackground = Color(0xFF0C1425);
  static const Color darkSurface = Color(0xFF19233B);
  static const Color darkPrimary = Color(0xFF6F6CF0);
  static const Color darkTextPrimary = Color(0xFFF3F5FB);
  static const Color darkTextSecondary = Color(0xFFA6ACC4);
  static const Color darkBorder = Color(0xFF2A3555);

  // Semantic - used for anything that means "good/caution/bad" regardless
  // of priority or task status specifically (e.g. a success snackbar, a
  // warning banner, a destructive action's accent).
  static const Color success = Color(0xFF23AB64);
  static const Color warning = Color(0xFFF4BE56);
  static const Color error = Color(0xFFD95155);
  static const Color info = brandBlue;

  static const Map<TaskPriority, Color> priority = {
    TaskPriority.low: brandBlue,
    TaskPriority.medium: warning,
    TaskPriority.high: error,
    TaskPriority.urgent: Color(0xFFA3272C), // deeper than `high` - ranks above it
  };

  static const Map<TaskPriority, String> priorityLabel = {
    TaskPriority.low: 'Low',
    TaskPriority.medium: 'Medium',
    TaskPriority.high: 'High',
    TaskPriority.urgent: 'Urgent',
  };

  static const Map<TaskDisplayStatus, Color> status = {
    TaskDisplayStatus.pending: brandBlue,
    TaskDisplayStatus.inProgress: brandCyan,
    TaskDisplayStatus.completed: success,
    TaskDisplayStatus.overdue: error,
    TaskDisplayStatus.snoozed: warning,
    TaskDisplayStatus.cancelled: Color(0xFF9E9E9E),
  };

  static const Map<TaskDisplayStatus, String> statusLabel = {
    TaskDisplayStatus.pending: 'Pending',
    TaskDisplayStatus.inProgress: 'In Progress',
    TaskDisplayStatus.completed: 'Completed',
    TaskDisplayStatus.overdue: 'Overdue',
    TaskDisplayStatus.snoozed: 'Snoozed',
    TaskDisplayStatus.cancelled: 'Cancelled',
  };
}

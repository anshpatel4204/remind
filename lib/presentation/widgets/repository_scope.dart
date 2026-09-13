import 'package:flutter/widgets.dart';

import '../../data/repositories/app_repositories.dart';

/// Makes one shared [AppRepositories] instance available to the widget
/// tree, so feature screens reach the data layer through
/// `RepositoryScope.of(context)` instead of constructing their own
/// repositories or touching SQL/the database directly.
class RepositoryScope extends InheritedWidget {
  const RepositoryScope(
      {super.key, required this.repositories, required super.child});

  final AppRepositories repositories;

  static AppRepositories of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RepositoryScope>();
    assert(scope != null, 'No RepositoryScope found in context');
    return scope!.repositories;
  }

  @override
  bool updateShouldNotify(RepositoryScope oldWidget) =>
      repositories != oldWidget.repositories;
}

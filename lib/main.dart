import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/repositories/app_repositories.dart';
import 'presentation/widgets/main_shell.dart';
import 'presentation/widgets/repository_scope.dart';

void main() {
  runApp(const RemindApp());
}

/// Root widget for REmind.
///
/// [repositories] can be injected (e.g. by tests, backed by an in-memory
/// FFI database) instead of relying on the default, which lazily builds
/// its own [AppRepositories] wired to the real on-device SQLite database.
class RemindApp extends StatelessWidget {
  const RemindApp({super.key, this.repositories});

  final AppRepositories? repositories;

  @override
  Widget build(BuildContext context) {
    return RepositoryScope(
      repositories: repositories ?? AppRepositories(),
      child: MaterialApp(
        title: 'REmind',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const MainShell(),
      ),
    );
  }
}

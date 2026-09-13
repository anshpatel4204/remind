import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../data/models/category_model.dart';
import '../../../../presentation/widgets/remind_empty_state.dart';
import '../../../../presentation/widgets/remind_error_state.dart';
import '../../../../presentation/widgets/remind_loading_state.dart';
import '../../../../presentation/widgets/repository_scope.dart';

/// Lets the user create, rename, and delete custom categories. The 7
/// default categories (Work, Study, Personal, Finance, Shopping, Health,
/// Other) can be renamed and recolored but never deleted, so there is
/// always a baseline set of categories to assign tasks to (enforced by
/// [CategoryRepository.deleteCategory]).
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late Future<_CategoriesData> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<_CategoriesData> _load() async {
    final repos = RepositoryScope.of(context);
    final categories = await repos.categoryRepository.getAllCategories();
    final counts = <int, int>{};
    for (final category in categories) {
      if (category.id == null) continue;
      final tasks = await repos.taskRepository.getAllTasks(categoryId: category.id);
      counts[category.id!] = tasks.length;
    }
    return _CategoriesData(categories: categories, taskCounts: counts);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _showCategoryDialog({CategoryModel? existing}) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    final formKey = GlobalKey<FormState>();
    String? selectedColorHex = existing?.color;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New category' : 'Rename category'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                Text('Color', style: Theme.of(dialogContext).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final hex in kCategoryColorSwatches)
                      _ColorSwatch(
                        hex: hex,
                        selected: selectedColorHex == hex,
                        onTap: () => setDialogState(() => selectedColorHex = hex),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = controller.text.trim();
    if (!mounted) return;
    final repos = RepositoryScope.of(context);
    if (existing == null) {
      await repos.categoryRepository.createCategory(name: name, color: selectedColorHex);
    } else {
      await repos.categoryRepository.updateCategory(
        existing.copyWith(name: name, color: selectedColorHex),
      );
    }
    if (!mounted) return;
    _reload();
  }

  Future<void> _confirmDelete(CategoryModel category) async {
    final repos = RepositoryScope.of(context);
    // Deleting a category leaves any tasks that used it with category_id =
    // null (ON DELETE SET NULL) rather than deleting them - this look-up is
    // just so the confirmation dialog can tell the user how many tasks
    // that will affect, not to block or change the deletion itself.
    final tasksUsingIt = await repos.taskRepository.getAllTasks(categoryId: category.id);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          tasksUsingIt.isEmpty
              ? '"${category.name}" will be permanently deleted.'
              : '"${category.name}" will be deleted. ${tasksUsingIt.length} '
                  '${tasksUsingIt.length == 1 ? 'task' : 'tasks'} using it will become '
                  'Uncategorized - they will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;
    await RepositoryScope.of(context).categoryRepository.deleteCategory(category.id!);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: FutureBuilder<_CategoriesData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return REmindErrorState(
              message: 'Something went wrong loading your categories.',
              onRetry: _reload,
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const REmindLoadingState();
          }
          final data = snapshot.data!;
          final categories = data.categories;
          if (categories.isEmpty) {
            return const REmindEmptyState(
              icon: Icons.category_outlined,
              title: 'No categories yet',
              message: 'Tap + to create your first category.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final color = colorFromHex(category.color) ?? kDefaultCategoryColors[category.name];
              final effectiveColor = color ?? Theme.of(context).colorScheme.primary;
              final icon = kDefaultCategoryIcons[category.name] ?? kFallbackCategoryIcon;
              final count = category.id == null ? 0 : (data.taskCounts[category.id!] ?? 0);
              return Card(
                child: ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: effectiveColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: effectiveColor),
                  ),
                  title: Text(category.name),
                  subtitle: Text('$count ${count == 1 ? 'task' : 'tasks'}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Category options',
                    onSelected: (value) {
                      if (value == 'edit') _showCategoryDialog(existing: category);
                      if (value == 'delete') _confirmDelete(category);
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Rename / recolor')),
                      if (!category.isDefault)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCategoryDialog(),
        tooltip: 'New category',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.hex, required this.selected, required this.onTap});

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(hex) ?? Theme.of(context).colorScheme.secondaryContainer;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
      ),
    );
  }
}

/// The Categories screen's loaded state: the category list plus a
/// per-category task count (computed client-side from
/// [TaskRepository.getAllTasks], no new repository method) so each row can
/// show "N tasks" like the reference.
class _CategoriesData {
  const _CategoriesData({required this.categories, required this.taskCounts});

  final List<CategoryModel> categories;
  final Map<int, int> taskCounts;
}

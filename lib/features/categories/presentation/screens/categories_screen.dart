import 'package:flutter/material.dart';

import '../../../../core/constants/category_colors.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../data/models/category_model.dart';
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
  late Future<List<CategoryModel>> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<List<CategoryModel>> _load() =>
      RepositoryScope.of(context).categoryRepository.getAllCategories();

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
          content: Form(
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
      body: FutureBuilder<List<CategoryModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final category = categories[index];
              final color = colorFromHex(category.color) ?? kDefaultCategoryColors[category.name];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color ?? Theme.of(context).colorScheme.secondaryContainer,
                    radius: 12,
                  ),
                  title: Text(category.name),
                  subtitle: category.isDefault ? const Text('Default category') : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename',
                        onPressed: () => _showCategoryDialog(existing: category),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip:
                            category.isDefault ? 'Default categories cannot be deleted' : 'Delete',
                        onPressed: category.isDefault ? null : () => _confirmDelete(category),
                      ),
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

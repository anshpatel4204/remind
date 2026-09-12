import 'package:flutter/material.dart';

import '../../../../data/models/tag_model.dart';
import '../../../../presentation/widgets/repository_scope.dart';

/// Lets the user create, rename, and delete tags. Deleting a tag removes
/// it from any tasks that had it (the task_tags join row cascades via its
/// foreign key - see [TagRepository.deleteTag]) but never deletes the
/// tasks themselves.
class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  late Future<List<TagModel>> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _future = _load();
    }
  }

  Future<List<TagModel>> _load() => RepositoryScope.of(context).tagRepository.getAllTags();

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _showTagDialog({TagModel? existing}) async {
    final controller = TextEditingController(text: existing?.name ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? 'New tag' : 'Rename tag'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag name'),
            validator: (value) =>
                (value == null || value.trim().isEmpty) ? 'Name is required' : null,
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
    );

    if (result != true) return;
    final name = controller.text.trim();
    if (!mounted) return;
    final repos = RepositoryScope.of(context);
    if (existing == null) {
      await repos.tagRepository.createTag(name: name);
    } else {
      await repos.tagRepository.updateTag(existing.copyWith(name: name));
    }
    if (!mounted) return;
    _reload();
  }

  Future<void> _confirmDelete(TagModel tag) async {
    final repos = RepositoryScope.of(context);
    final taskIds = await repos.tagRepository.getTaskIdsForTag(tag.id!);

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete tag?'),
        content: Text(
          taskIds.isEmpty
              ? '"${tag.name}" will be permanently deleted.'
              : '"${tag.name}" will be deleted and removed from ${taskIds.length} '
                  '${taskIds.length == 1 ? 'task' : 'tasks'} - the tasks themselves will not '
                  'be deleted.',
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
    await RepositoryScope.of(context).tagRepository.deleteTag(tag.id!);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: FutureBuilder<List<TagModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final tags = snapshot.data!;
          if (tags.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.label_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text('No tags yet', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Tap + to create your first tag.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            itemCount: tags.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final tag = tags[index];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.label_outline),
                  title: Text('#${tag.name}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Rename',
                        onPressed: () => _showTagDialog(existing: tag),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Delete',
                        onPressed: () => _confirmDelete(tag),
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
        onPressed: () => _showTagDialog(),
        tooltip: 'New tag',
        child: const Icon(Icons.add),
      ),
    );
  }
}

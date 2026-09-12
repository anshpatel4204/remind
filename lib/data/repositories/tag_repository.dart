import '../datasources/tag_data_source.dart';
import '../datasources/task_tag_data_source.dart';
import '../models/tag_model.dart';

/// Application-facing operations for tags, including their task
/// associations.
class TagRepository {
  TagRepository(this._dataSource, this._taskTagDataSource);

  final TagDataSource _dataSource;
  final TaskTagDataSource _taskTagDataSource;

  Future<TagModel> createTag({required String name, String? color}) async {
    final tag = TagModel(name: name, color: color, createdAt: DateTime.now());
    final id = await _dataSource.insert(tag);
    return tag.copyWith(id: id);
  }

  Future<TagModel?> getTag(int id) => _dataSource.getById(id);

  Future<List<TagModel>> getAllTags() => _dataSource.getAll();

  Future<void> updateTag(TagModel tag) async {
    if (tag.id == null) {
      throw ArgumentError('Cannot update a tag with no id');
    }
    await _dataSource.update(tag);
  }

  /// Deleting a tag also removes its task_tags associations via the
  /// ON DELETE CASCADE foreign key - the tasks themselves are unaffected.
  Future<void> deleteTag(int id) => _dataSource.delete(id);

  Future<List<int>> getTaskIdsForTag(int tagId) => _taskTagDataSource.getTaskIdsForTag(tagId);
}

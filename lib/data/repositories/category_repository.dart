import '../datasources/category_data_source.dart';
import '../models/category_model.dart';

/// Application-facing operations for categories. This is the only layer the
/// UI should talk to for category data - it never sees SQL or raw maps.
class CategoryRepository {
  CategoryRepository(this._dataSource);

  final CategoryDataSource _dataSource;

  Future<CategoryModel> createCategory({
    required String name,
    String? color,
    String? iconName,
  }) async {
    final category = CategoryModel(
      name: name,
      color: color,
      iconName: iconName,
      createdAt: DateTime.now(),
    );
    final id = await _dataSource.insert(category);
    return category.copyWith(id: id);
  }

  Future<CategoryModel?> getCategory(int id) => _dataSource.getById(id);

  Future<List<CategoryModel>> getAllCategories() => _dataSource.getAll();

  Future<void> updateCategory(CategoryModel category) async {
    if (category.id == null) {
      throw ArgumentError('Cannot update a category with no id');
    }
    await _dataSource.update(category);
  }

  /// Deletes a category. Default categories (Work, Study, Personal,
  /// Finance, Shopping, Health, Other) cannot be deleted - only renamed or
  /// restyled - so there is always a baseline set of categories to assign
  /// tasks to. Deleting a non-default category leaves any tasks assigned to
  /// it with category_id = null (see the ON DELETE SET NULL foreign key)
  /// rather than deleting those tasks.
  Future<void> deleteCategory(int id) async {
    final category = await _dataSource.getById(id);
    if (category == null) return;
    if (category.isDefault) {
      throw StateError('Default category "${category.name}" cannot be deleted');
    }
    await _dataSource.delete(id);
  }
}

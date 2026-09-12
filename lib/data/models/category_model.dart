import '../database/db_constants.dart';

/// A task category (e.g. Work, Study, Personal). Seven default categories
/// are seeded on first run; the user may also add their own.
class CategoryModel {
  const CategoryModel({
    this.id,
    required this.name,
    this.color,
    this.iconName,
    this.isDefault = false,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String? color;
  final String? iconName;
  final bool isDefault;
  final DateTime createdAt;

  factory CategoryModel.fromMap(Map<String, Object?> map) {
    return CategoryModel(
      id: map[CategoriesTable.id] as int?,
      name: map[CategoriesTable.categoryName] as String,
      color: map[CategoriesTable.color] as String?,
      iconName: map[CategoriesTable.iconName] as String?,
      isDefault: (map[CategoriesTable.isDefault] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[CategoriesTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      CategoriesTable.categoryName: name,
      CategoriesTable.color: color,
      CategoriesTable.iconName: iconName,
      CategoriesTable.isDefault: isDefault ? 1 : 0,
      CategoriesTable.createdAt: createdAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map[CategoriesTable.id] = id;
    }
    return map;
  }

  CategoryModel copyWith({
    int? id,
    String? name,
    String? color,
    String? iconName,
    bool? isDefault,
    DateTime? createdAt,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      iconName: iconName ?? this.iconName,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'CategoryModel(id: $id, name: $name)';
}

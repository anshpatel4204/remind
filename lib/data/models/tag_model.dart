import '../database/db_constants.dart';

/// A user-defined tag that can be attached to any number of tasks.
class TagModel {
  const TagModel({
    this.id,
    required this.name,
    this.color,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final String? color;
  final DateTime createdAt;

  factory TagModel.fromMap(Map<String, Object?> map) {
    return TagModel(
      id: map[TagsTable.id] as int?,
      name: map[TagsTable.tagName] as String,
      color: map[TagsTable.color] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map[TagsTable.createdAt] as int),
    );
  }

  Map<String, Object?> toMap({bool includeId = false}) {
    final map = <String, Object?>{
      TagsTable.tagName: name,
      TagsTable.color: color,
      TagsTable.createdAt: createdAt.millisecondsSinceEpoch,
    };
    if (includeId && id != null) {
      map[TagsTable.id] = id;
    }
    return map;
  }

  TagModel copyWith({int? id, String? name, String? color, DateTime? createdAt}) {
    return TagModel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'TagModel(id: $id, name: $name)';
}

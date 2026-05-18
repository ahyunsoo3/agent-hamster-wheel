/// Domain model for a hierarchical folder (decoupled from persistence rows).
const Object _unset = Object();

class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentFolderId,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final String? parentFolderId;

  /// Example field introduced in schema v2 (see migrations).
  final int sortOrder;

  Folder copyWith({
    String? id,
    String? name,
    Object? parentFolderId = _unset,
    int? sortOrder,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentFolderId: parentFolderId == _unset
          ? this.parentFolderId
          : parentFolderId as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

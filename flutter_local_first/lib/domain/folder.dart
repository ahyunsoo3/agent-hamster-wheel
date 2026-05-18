/// Sentinel used by [Folder.copyWith] to distinguish "omitted" from an explicit `null`.
const _unset = Object();

/// Domain model for a hierarchical folder (decoupled from persistence rows).
class Folder {
  const Folder({
    required this.id,
    required this.name,
    this.parentFolderId,
    this.sortOrder = 0,
  }) : assert(id != '', 'Folder.id must not be empty'),
       assert(sortOrder >= 0, 'Folder.sortOrder must be non-negative');

  final String id;
  final String name;
  final String? parentFolderId;

  /// Example field introduced in schema v2 (see migrations).
  final int sortOrder;

  /// Pass [parentFolderId] as `null` to explicitly move the folder to the root.
  /// Omit [parentFolderId] entirely to keep the existing value.
  Folder copyWith({
    String? id,
    String? name,
    Object? parentFolderId = _unset,
    int? sortOrder,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      parentFolderId: identical(parentFolderId, _unset)
          ? this.parentFolderId
          : parentFolderId as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Folder &&
          id == other.id &&
          name == other.name &&
          parentFolderId == other.parentFolderId &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode => Object.hash(id, name, parentFolderId, sortOrder);

  @override
  String toString() =>
      'Folder(id: $id, name: $name, parentFolderId: $parentFolderId, '
      'sortOrder: $sortOrder)';
}

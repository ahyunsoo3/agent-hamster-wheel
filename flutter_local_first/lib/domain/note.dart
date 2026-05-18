import 'package:collection/collection.dart';

/// Sentinel used by [Note.copyWith] to distinguish "omitted" from an explicit `null`.
const _unset = Object();

/// Value equality helper for the [Note.tags] list.
const _listEq = ListEquality<String>();

/// Domain model for a note. [content] is plain UTF-8 text suitable for Markdown parsers.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    required this.tags,
    this.folderId,
  });

  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final String? folderId;

  /// Pass [folderId] as `null` to explicitly clear the folder assignment.
  /// Omit [folderId] entirely to keep the existing value.
  Note copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    Object? folderId = _unset,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      folderId: identical(folderId, _unset)
          ? this.folderId
          : folderId as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note &&
          id == other.id &&
          title == other.title &&
          content == other.content &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt &&
          _listEq.equals(tags, other.tags) &&
          folderId == other.folderId;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    content,
    createdAt,
    updatedAt,
    _listEq.hash(tags),
    folderId,
  );

  @override
  String toString() =>
      'Note(id: $id, title: $title, folderId: $folderId, '
      'tags: $tags, updatedAt: $updatedAt)';
}

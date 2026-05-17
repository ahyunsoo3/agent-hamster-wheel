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

  Note copyWith({
    String? id,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
    String? folderId,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
      folderId: folderId ?? this.folderId,
    );
  }
}

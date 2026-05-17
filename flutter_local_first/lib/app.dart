import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'data/local_repositories.dart';
import 'domain/folder.dart';
import 'domain/note.dart';

/// Root widget; accepts [database] for tests / benchmarks.
class LocalFirstNotesApp extends StatefulWidget {
  const LocalFirstNotesApp({super.key, required this.database});

  final AppDatabase database;

  @override
  State<LocalFirstNotesApp> createState() => _LocalFirstNotesAppState();
}

class _LocalFirstNotesAppState extends State<LocalFirstNotesApp> {
  late final NotesLocalRepository _notes;
  late final FoldersLocalRepository _folders;

  @override
  void initState() {
    super.initState();
    _notes = NotesLocalRepository(widget.database);
    _folders = FoldersLocalRepository(widget.database);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local-first notes',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Notes & folders'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Notes'),
                Tab(text: 'Folders'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _NotesTab(notes: _notes),
              StreamBuilder<List<Folder>>(
                stream: _folders.watchFolders(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final folders = snap.data ?? const [];
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: folders.length,
                    itemBuilder: (context, i) {
                      final f = folders[i];
                      return ListTile(
                        title: Text(f.name),
                        subtitle: Text(
                          f.parentFolderId == null
                              ? 'Root'
                              : 'Parent: ${f.parentFolderId}',
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesTab extends StatefulWidget {
  const _NotesTab({required this.notes});

  final NotesLocalRepository notes;

  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  final TextEditingController _search = TextEditingController();
  late Stream<List<Note>> _noteStream;

  @override
  void initState() {
    super.initState();
    _noteStream = widget.notes.watchNotes();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _bindNoteStream() {
    final qTrimmed = _search.text.trim();
    final ftsQuery = fts5PrefixQuery(qTrimmed);
    _noteStream = ftsQuery.isEmpty
        ? widget.notes.watchNotes()
        : widget.notes.watchSearchResults(qTrimmed);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trimmedQuery = _search.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Full-text search (title + content)',
            ),
            onChanged: (_) => _bindNoteStream(),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Note>>(
            stream: _noteStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return Center(
                  child: Text(
                    trimmedQuery.isEmpty ? 'No notes yet' : 'No matches',
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final n = list[i];
                  return Card(
                    child: ListTile(
                      title: Text(n.title),
                      subtitle: Text(
                        '${n.tags.join(", ")} · ${n.updatedAt.toLocal()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

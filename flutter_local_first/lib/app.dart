import 'package:flutter/material.dart';

import 'database/app_database.dart';
import 'data/local_repositories.dart';
import 'domain/folder.dart';
import 'domain/note.dart';

/// Chooses full-list vs FTS stream using the same trimmed query + tokenization as the repository.
Stream<List<Note>> _notesStreamForSearchField(
  NotesLocalRepository repo,
  String rawSearchText,
) {
  final trimmed = rawSearchText.trim();
  return fts5HasSearchableTokens(trimmed)
      ? repo.watchSearchResults(trimmed)
      : repo.watchNotes();
}

/// Root widget; accepts [database] for tests / benchmarks.
class LocalFirstNotesApp extends StatefulWidget {
  const LocalFirstNotesApp({super.key, required this.database});

  final AppDatabase database;

  @override
  State<LocalFirstNotesApp> createState() => _LocalFirstNotesAppState();
}

class _LocalFirstNotesAppState extends State<LocalFirstNotesApp> {
  late NotesLocalRepository _notes;
  late FoldersLocalRepository _folders;

  @override
  void initState() {
    super.initState();
    _notes = NotesLocalRepository(widget.database);
    _folders = FoldersLocalRepository(widget.database);
  }

  @override
  void didUpdateWidget(covariant LocalFirstNotesApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.database, widget.database)) {
      _notes = NotesLocalRepository(widget.database);
      _folders = FoldersLocalRepository(widget.database);
    }
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
              _FoldersTab(folders: _folders),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoldersTab extends StatefulWidget {
  const _FoldersTab({required this.folders});

  final FoldersLocalRepository folders;

  @override
  State<_FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends State<_FoldersTab> {
  late Stream<List<Folder>> _folderStream;

  @override
  void initState() {
    super.initState();
    _folderStream = widget.folders.watchFolders();
  }

  @override
  void didUpdateWidget(covariant _FoldersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.folders, widget.folders)) {
      _folderStream = widget.folders.watchFolders();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Folder>>(
      stream: _folderStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final folderList = snap.data ?? const [];
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: folderList.length,
          itemBuilder: (context, i) {
            final f = folderList[i];
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
    _noteStream = _notesStreamForSearchField(widget.notes, _search.text);
  }

  @override
  void didUpdateWidget(covariant _NotesTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notes, widget.notes)) {
      _noteStream = _notesStreamForSearchField(widget.notes, _search.text);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _bindNoteStream() {
    _noteStream = _notesStreamForSearchField(widget.notes, _search.text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final qTrimmed = _search.text.trim();
    final ftsActive = fts5HasSearchableTokens(qTrimmed);

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
                  child: Text(ftsActive ? 'No matches' : 'No notes yet'),
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

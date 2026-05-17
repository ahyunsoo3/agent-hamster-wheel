# Standardized Research Prompt Template

This document defines the benchmark prompt used to evaluate local-first development ecosystems. Guide-generation workflows should pass this template to agents, filling in the `[TARGET TECH STACK]` section for each trial.

**Quick copy:** run `./scripts/copy-research-prompt.sh flutter` (or `react-native`, `tauri`, `template`) to copy the filled prompt to your clipboard. Use `--print` to print instead, or run with no arguments for an interactive menu.

## Base prompt

```text
Act as a Principal Software Engineer and System Architect. This prompt is part of a research benchmark evaluating local-first development ecosystems. Your task is to provide a complete, production-ready implementation of a local-first data layer based strictly on the specification below.

[TARGET TECH STACK]
- Framework & Language: [Insert e.g., "Flutter + Dart" OR "React Native + TypeScript" OR "React + Tauri + TypeScript"]
- Recommended Local Database Engine: [Insert e.g., "Isar" OR "WatermelonDB" OR "RxDB/SQLite"]

---

1. FUNCTIONAL SPECIFICATION & DATA SCHEMA
The implementation must strictly support the following data models and relationships:

A. Note Model
- id: String (Unique Identifier / UUID)
- title: String
- content: String (To be stored in a format optimized for text/markdown parsers)
- createdAt: DateTime / Timestamp
- updatedAt: DateTime / Timestamp
- tags: List/Array of Strings
- folderId: String (Nullable, referencing a Parent Folder)

B. Folder Model
- id: String (Unique Identifier)
- name: String
- parentFolderId: String (Nullable, supporting a self-referencing hierarchy)

---

2. ARCHITECTURAL REQUIREMENTS
To ensure a fair cross-language comparison, your code implementation must provide:

- Strict Type Safety: Provide full interface, class, or type definitions for all schemas and models.
- Reactive UI Binding: Data operations must expose streams, observables, or reactive state triggers so the UI updates automatically when data changes.
- Performance & Non-Blocking I/O: Database reads, writes, and searches must run asynchronously without blocking the main rendering thread.
- Local Full-Text Search (FTS): Implement a query function utilizing the database engine's native indexing capabilities to execute a "search-as-you-type" query against both the 'title' and 'content' fields simultaneously.
- Schema Migration Blueprint: A brief code structure showing how a database version upgrade (e.g., adding a new field) is cleanly handled locally.

---

3. EXPECTED OUTPUT
Please structure your response with the following exact sections to facilitate comparative analysis:

1. Dependencies Configuration: (e.g., pubspec.yaml, package.json, or Cargo.toml requirements).
2. Database Schema & Model Definitions: Complete code with required database engine annotations/decorators.
3. Repository / Service Layer Implementation: A clean class or set of functions providing full CRUD operations, reactive data stream exposure, and the Full-Text Search query.
4. Database Initialization & Migration Example: The setup code demonstrating database instantiation and migration logic.
```

## How to fill the `[TARGET TECH STACK]` section

Replace the placeholder block in the base prompt with one of the trial configurations below.

### Trial 1: Flutter

```text
[TARGET TECH STACK]
- Framework & Language: Flutter (Dart)
- Recommended Local Database Engine: Isar (or Drift if relational approach is preferred)
```

### Trial 2: React Native

```text
[TARGET TECH STACK]
- Framework & Language: React Native (TypeScript / Expo-compatible)
- Recommended Local Database Engine: WatermelonDB (or OP-SQLite)
```

### Trial 3: Tauri / Desktop

```text
[TARGET TECH STACK]
- Framework & Language: React + Tauri (TypeScript)
- Recommended Local Database Engine: RxDB or Tauri-Plugin-SQL (SQLite)
```

#!/usr/bin/env bash
# Copy the standardized research prompt to the clipboard, with an optional tech stack.
#
# Canonical prompt text lives in this script (embedded below). The markdown file at
# prompts/standardized-research-prompt-template.md mirrors it for documentation;
# pass --file PATH to parse base + trial blocks from a different markdown file instead.
#
# Usage:
#   ./scripts/copy-research-prompt.sh [stack]
#   ./scripts/copy-research-prompt.sh              # interactive menu
#   ./scripts/copy-research-prompt.sh --list
#   ./scripts/copy-research-prompt.sh --print flutter
#
# Stack aliases:
#   flutter | 1
#   react-native | react | rn | 2
#   tauri | desktop | 3
#   template | base | placeholder   (keep [TARGET TECH STACK] placeholders)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_TEMPLATE="${REPO_ROOT}/prompts/standardized-research-prompt-template.md"
TEMPLATE_FILE="${DEFAULT_TEMPLATE}"
# When 1 (default), use embedded_* prompts. When --file is passed, parse TEMPLATE_FILE with awk.
USE_EMBEDDED_PROMPTS=1

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [stack]

Copy the research benchmark prompt to your clipboard (or stdout with --print).

Stacks (optional — pick one or run without args for a menu):
  flutter, 1              Flutter + Isar/Drift
  react-native, react, rn, 2   React Native + WatermelonDB/OP-SQLite
  tauri, desktop, 3       React + Tauri + RxDB/SQLite
  template, base          Base prompt with [TARGET TECH STACK] placeholders

Options:
  -h, --help              Show this help
  -l, --list              List available stacks
  -p, --print             Print to stdout instead of copying
  -f, --file PATH         Use a different template markdown file

Examples:
  $(basename "$0") flutter
  $(basename "$0") --print react-native
  $(basename "$0") tauri

Source reference:
  Embedded prompt definitions in this script (research_prompt_base / research_prompt_stack_*).
  Markdown mirror: prompts/standardized-research-prompt-template.md
EOF
}

# --- Embedded canonical prompts (keep in sync with standardized-research-prompt-template.md) ---

research_prompt_base() {
  cat <<'EOF'
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
EOF
}

research_prompt_stack_template() {
  cat <<'EOF'
[TARGET TECH STACK]
- Framework & Language: [Insert e.g., "Flutter + Dart" OR "React Native + TypeScript" OR "React + Tauri + TypeScript"]
- Recommended Local Database Engine: [Insert e.g., "Isar" OR "WatermelonDB" OR "RxDB/SQLite"]
EOF
}

research_prompt_stack_flutter() {
  cat <<'EOF'
[TARGET TECH STACK]
- Framework & Language: Flutter (Dart)
- Recommended Local Database Engine: Isar (or Drift if relational approach is preferred)
EOF
}

research_prompt_stack_react_native() {
  cat <<'EOF'
[TARGET TECH STACK]
- Framework & Language: React Native (TypeScript / Expo-compatible)
- Recommended Local Database Engine: WatermelonDB (or OP-SQLite)
EOF
}

research_prompt_stack_tauri() {
  cat <<'EOF'
[TARGET TECH STACK]
- Framework & Language: React + Tauri (TypeScript)
- Recommended Local Database Engine: RxDB or Tauri-Plugin-SQL (SQLite)
EOF
}

# First fenced \`\`\`text block in the file (base prompt).
extract_base_prompt_from_file() {
  awk '
    /^```text$/ && base == 0 { in_base = 1; next }
    in_base && /^```$/ { exit }
    in_base { print }
  ' "${TEMPLATE_FILE}"
}

# Fenced \`\`\`text block under a trial heading (e.g. "### Trial 1: Flutter").
extract_trial_block_from_file() {
  local heading="$1"
  awk -v heading="${heading}" '
    $0 ~ heading { found = 1; next }
    found && /^```text$/ { in_block = 1; next }
    found && in_block && /^```$/ { exit }
    found && in_block { print }
  ' "${TEMPLATE_FILE}"
}

extract_base_prompt() {
  if [[ "${USE_EMBEDDED_PROMPTS}" -eq 1 ]]; then
    research_prompt_base
  else
    extract_base_prompt_from_file
  fi
}

normalize_stack() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${raw}" in
    "" | template | base | placeholder) echo "template" ;;
    flutter | 1) echo "flutter" ;;
    react-native | react | reactnative | rn | 2) echo "react-native" ;;
    tauri | desktop | 3) echo "tauri" ;;
    *)
      die "unknown stack: ${1}. Run with --list for options."
      ;;
  esac
}

stack_block_for() {
  local stack="$1"
  if [[ "${USE_EMBEDDED_PROMPTS}" -eq 1 ]]; then
    case "${stack}" in
      template) research_prompt_stack_template ;;
      flutter) research_prompt_stack_flutter ;;
      react-native) research_prompt_stack_react_native ;;
      tauri) research_prompt_stack_tauri ;;
    esac
  else
    case "${stack}" in
      template) research_prompt_stack_template ;;
      flutter) extract_trial_block_from_file "### Trial 1: Flutter" ;;
      react-native) extract_trial_block_from_file "### Trial 2: React Native" ;;
      tauri) extract_trial_block_from_file "### Trial 3: Tauri" ;;
    esac
  fi
}

build_prompt() {
  local stack="$1"
  local base stack_file

  base="$(extract_base_prompt)"
  stack_file="$(mktemp "${TMPDIR:-/tmp}/research-prompt-stack.XXXXXX")"
  stack_block_for "${stack}" >"${stack_file}"

  [[ -n "${base}" ]] || die "could not read base prompt (embedded or ${TEMPLATE_FILE})"
  [[ -s "${stack_file}" ]] || die "could not read stack block for: ${stack}"

  printf '%s\n\n' 'Implement based on the following plan.'
  awk -v stack_file="${stack_file}" '
    /^\[TARGET TECH STACK\]$/ {
      while ((getline line < stack_file) > 0) {
        print line
      }
      close(stack_file)
      skip = 1
      next
    }
    skip && /^- Recommended Local Database Engine:/ { skip = 0; next }
    skip { next }
    { print }
  ' <<<"${base}"

  rm -f "${stack_file}"
}

copy_to_clipboard() {
  local text="$1"
  if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "${text}" | pbcopy
    return 0
  fi
  if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "${text}" | wl-copy
    return 0
  fi
  if command -v xclip >/dev/null 2>&1; then
    printf '%s' "${text}" | xclip -selection clipboard
    return 0
  fi
  if command -v xsel >/dev/null 2>&1; then
    printf '%s' "${text}" | xsel --clipboard --input
    return 0
  fi
  return 1
}

list_stacks() {
  cat <<EOF
Available stacks:
  flutter (1)         Flutter (Dart) + Isar/Drift
  react-native (2)    React Native (TypeScript) + WatermelonDB/OP-SQLite
  tauri (3)           React + Tauri (TypeScript) + RxDB/SQLite
  template (base)     Unfilled [TARGET TECH STACK] placeholders
EOF
}

pick_stack_interactive() {
  echo "Select a tech stack:" >&2
  select choice in "flutter" "react-native" "tauri" "template (placeholders)" "cancel"; do
    case "${REPLY}" in
      1) echo "flutter"; return ;;
      2) echo "react-native"; return ;;
      3) echo "tauri"; return ;;
      4) echo "template"; return ;;
      5) die "cancelled" ;;
      *) echo "Invalid choice. Try again." >&2 ;;
    esac
  done
}

PRINT_ONLY=0
STACK_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    -l | --list) list_stacks; exit 0 ;;
    -p | --print) PRINT_ONLY=1; shift ;;
    -f | --file)
      shift
      [[ $# -gt 0 ]] || die "--file requires a path"
      TEMPLATE_FILE="$1"
      USE_EMBEDDED_PROMPTS=0
      [[ -f "${TEMPLATE_FILE}" ]] || die "template not found: ${TEMPLATE_FILE}"
      shift
      ;;
    --) shift; break ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *) STACK_ARG="$1"; shift ;;
  esac
done

if [[ -z "${STACK_ARG}" && $# -gt 0 ]]; then
  STACK_ARG="$1"
fi

if [[ -z "${STACK_ARG}" ]]; then
  if [[ -t 0 ]]; then
    STACK_ARG="$(pick_stack_interactive)"
  else
    usage >&2
    die "stack argument required (non-interactive)"
  fi
fi

STACK="$(normalize_stack "${STACK_ARG}")"
PROMPT="$(build_prompt "${STACK}")"

if [[ "${PRINT_ONLY}" -eq 1 ]]; then
  printf '%s\n' "${PROMPT}"
  exit 0
fi

if copy_to_clipboard "${PROMPT}"; then
  echo "Copied research prompt (${STACK}) to clipboard."
  if [[ "${USE_EMBEDDED_PROMPTS}" -eq 1 ]]; then
    echo "Source: embedded prompt in scripts/copy-research-prompt.sh"
  else
    echo "Source: ${TEMPLATE_FILE} (parsed with awk)"
  fi
else
  echo "No clipboard tool found (pbcopy / wl-copy / xclip / xsel). Printing to stdout:" >&2
  printf '%s\n' "${PROMPT}"
fi

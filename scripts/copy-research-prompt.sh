#!/usr/bin/env bash
# Copy the standardized research prompt to the clipboard, with an optional tech stack.
#
# Equivalent to copying prompts/standardized-research-prompt-template.md (base block)
# with [TARGET TECH STACK] filled in for Flutter, React Native, or Tauri.
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
TEMPLATE_FILE="${REPO_ROOT}/prompts/standardized-research-prompt-template.md"

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

Source reference (base prompt body):
  @prompts/standardized-research-prompt-template.md (first text code block, lines 8-52)
EOF
}

[[ -f "${TEMPLATE_FILE}" ]] || die "template not found: ${TEMPLATE_FILE}"

# First fenced \`\`\`text block in the file (base prompt).
extract_base_prompt() {
  awk '
    /^```text$/ && base == 0 { in_base = 1; next }
    in_base && /^```$/ { exit }
    in_base { print }
  ' "${TEMPLATE_FILE}"
}

# Fenced \`\`\`text block under a trial heading (e.g. "### Trial 1: Flutter").
extract_trial_block() {
  local heading="$1"
  awk -v heading="${heading}" '
    $0 ~ heading { found = 1; next }
    found && /^```text$/ { in_block = 1; next }
    found && in_block && /^```$/ { exit }
    found && in_block { print }
  ' "${TEMPLATE_FILE}"
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
  case "${stack}" in
    template) echo "[TARGET TECH STACK]
- Framework & Language: [Insert e.g., \"Flutter + Dart\" OR \"React Native + TypeScript\" OR \"React + Tauri + TypeScript\"]
- Recommended Local Database Engine: [Insert e.g., \"Isar\" OR \"WatermelonDB\" OR \"RxDB/SQLite\"]" ;;
    flutter) extract_trial_block "### Trial 1: Flutter" ;;
    react-native) extract_trial_block "### Trial 2: React Native" ;;
    tauri) extract_trial_block "### Trial 3: Tauri" ;;
  esac
}

build_prompt() {
  local stack="$1"
  local base stack_file

  base="$(extract_base_prompt)"
  stack_file="$(mktemp "${TMPDIR:-/tmp}/research-prompt-stack.XXXXXX")"
  stack_block_for "${stack}" >"${stack_file}"

  [[ -n "${base}" ]] || die "could not read base prompt from ${TEMPLATE_FILE}"
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
  echo "Source: prompts/standardized-research-prompt-template.md (base block + Trial stack)"
else
  echo "No clipboard tool found (pbcopy / wl-copy / xclip / xsel). Printing to stdout:" >&2
  printf '%s\n' "${PROMPT}"
fi

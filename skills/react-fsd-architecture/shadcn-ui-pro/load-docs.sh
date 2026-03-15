#!/usr/bin/env bash
# load-docs.sh — Print shadcn-ui-pro docs to stdout for injection into AI context.
#
# Usage:
#   ./load-docs.sh                     # Print README (topic index)
#   ./load-docs.sh form                # Print form-guide.md
#   ./load-docs.sh category            # Print examples/category-selector.md
#   ./load-docs.sh event               # Print examples/event-form.md
#   ./load-docs.sh list                # Print list-components.md
#   ./load-docs.sh list-feature        # Print examples/list-feature.md
#   ./load-docs.sh input               # Print input-components.md
#   ./load-docs.sh typography          # Print typography.md
#   ./load-docs.sh hooks               # Print hooks.md
#   ./load-docs.sh button              # Print button.md
#   ./load-docs.sh badge               # Print badge.md
#   ./load-docs.sh alert-dialog        # Print alert-dialog.md
#   ./load-docs.sh all                 # Print all docs concatenated
#
# Example — pipe into clipboard (Windows Git Bash):
#   ./load-docs.sh form | clip
#
# Example — pass to Claude Code context:
#   ./load-docs.sh all > /tmp/shadcn-docs.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_file() {
  local file="$SCRIPT_DIR/$1"
  if [[ -f "$file" ]]; then
    echo "===== $1 ====="
    cat "$file"
    echo ""
  else
    echo "ERROR: File not found: $file" >&2
    exit 1
  fi
}

case "${1:-}" in
  form)
    print_file "form-guide.md"
    ;;
  category)
    print_file "examples/category-selector.md"
    ;;
  event)
    print_file "examples/event-form.md"
    ;;
  list)
    print_file "list-components.md"
    ;;
  list-feature)
    print_file "examples/list-feature.md"
    ;;
  input)
    print_file "input-components.md"
    ;;
  typography)
    print_file "typography.md"
    ;;
  hooks)
    print_file "hooks.md"
    ;;
  button)
    print_file "button.md"
    ;;
  badge)
    print_file "badge.md"
    ;;
  alert-dialog)
    print_file "alert-dialog.md"
    ;;
  all)
    print_file "README.md"
    print_file "form-guide.md"
    print_file "input-components.md"
    print_file "button.md"
    print_file "badge.md"
    print_file "typography.md"
    print_file "hooks.md"
    print_file "alert-dialog.md"
    print_file "list-components.md"
    print_file "examples/category-selector.md"
    print_file "examples/event-form.md"
    print_file "examples/list-feature.md"
    ;;
  ""|readme)
    print_file "README.md"
    ;;
  *)
    echo "Unknown topic: $1"
    echo "Available: form | input | button | badge | typography | hooks | alert-dialog | list | list-feature | category | event | all | readme"
    exit 1
    ;;
esac

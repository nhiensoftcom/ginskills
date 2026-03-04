#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Codebase Scanner
#
# Quick scan of the entire monorepo for common code quality
# issues. Auto-detects project directories.
#
# Usage:
#   ./scan-codebase.sh              # scan everything
#   ./scan-codebase.sh --json       # output as JSON
#
# Environment variables (override auto-detection):
#   BE_SRC=./my-backend/src  FE_SRC=./my-frontend/src  ./scan-codebase.sh
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Auto-detect project directories ─────────────────────────
detect_src() {
  local kind="$1"
  shift
  for candidate in "$@"; do
    if [ -d "$REPO_ROOT/$candidate/src" ]; then
      echo "$REPO_ROOT/$candidate/src"
      return
    fi
  done
  echo ""
}

BE_SRC="${BE_SRC:-$(detect_src backend backend be-* server api apps/api apps/backend)}"
FE_SRC="${FE_SRC:-$(detect_src frontend frontend web-* client apps/web apps/frontend)}"

JSON_MODE="${1:-}"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  Codebase Scanner                         ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# ─── Backend Scan ─────────────────────────────────────────────
if [ -n "$BE_SRC" ] && [ -d "$BE_SRC" ]; then
  BE_NAME="$(basename "$(dirname "$BE_SRC")")"
  echo "  ═══ Backend ($BE_NAME) ═══"
  echo ""

  # Count features
  FEATURE_COUNT=$(ls -1d "$BE_SRC/features"/*/ 2>/dev/null | wc -l | tr -d ' ')
  echo "  Feature modules: $FEATURE_COUNT"

  # Total TS files
  BE_TS_COUNT=$(find "$BE_SRC" -name "*.ts" | wc -l | tr -d ' ')
  echo "  TypeScript files: $BE_TS_COUNT"

  # Test files
  BE_TEST_COUNT=$(find "$BE_SRC" -name "*.spec.ts" -o -name "*.test.ts" 2>/dev/null | wc -l | tr -d ' ')
  echo "  Test files: $BE_TEST_COUNT"

  # Test coverage ratio
  if [ "$BE_TS_COUNT" -gt 0 ]; then
    COVERAGE_PCT=$(( BE_TEST_COUNT * 100 / BE_TS_COUNT ))
    echo "  Test file ratio: ${COVERAGE_PCT}%"
  fi

  echo ""
  echo "  Code quality indicators:"

  # any usage across backend
  ANY_COUNT=$(grep -r ": any\b" "$BE_SRC" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
  echo "    'any' type usage: $ANY_COUNT occurrences"

  # TODO/FIXME/HACK comments
  TODO_COUNT=$(grep -ri "TODO\|FIXME\|HACK\|XXX" "$BE_SRC" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
  echo "    TODO/FIXME/HACK: $TODO_COUNT comments"

  # console.log (should use structured logger)
  CONSOLE_COUNT=$(grep -r "console\.log\|console\.error\|console\.warn" "$BE_SRC" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
  echo "    console.* usage: $CONSOLE_COUNT (should use structured logger)"

  # Empty catch blocks
  EMPTY_CATCH=$(grep -r "catch.*{" "$BE_SRC" --include="*.ts" -A1 2>/dev/null | grep -c "^[[:space:]]*}" || true)
  echo "    Potentially empty catch blocks: $EMPTY_CATCH"

  # Modules without tests
  echo ""
  echo "  Modules without tests:"
  for mod_dir in "$BE_SRC/features"/*/; do
    mod_name=$(basename "$mod_dir")
    test_files=$(find "$mod_dir" -name "*.spec.ts" -o -name "*.test.ts" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$test_files" -eq 0 ]; then
      echo "    - $mod_name"
    fi
  done

  # Modules without Swagger docs
  echo ""
  echo "  Modules without Swagger decorators:"
  for mod_dir in "$BE_SRC/features"/*/; do
    mod_name=$(basename "$mod_dir")
    swagger=$(grep -r "@ApiTags\|@ApiOperation" "$mod_dir" 2>/dev/null | wc -l | tr -d ' ')
    controller=$(find "$mod_dir" -name "*.controller.ts" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$controller" -gt 0 ] && [ "$swagger" -eq 0 ]; then
      echo "    - $mod_name"
    fi
  done

  # Top any-heavy files
  echo ""
  echo "  Top 10 files by 'any' usage:"
  grep -rc ": any\b" "$BE_SRC" --include="*.ts" 2>/dev/null | grep -v ":0$" | sort -t: -k2 -rn | head -10 | while IFS=: read -r file count; do
    echo "    $count  ${file#$REPO_ROOT/}"
  done
else
  echo "  [skip] No backend source directory detected"
fi

# ─── Frontend Scan ────────────────────────────────────────────
echo ""
if [ -n "$FE_SRC" ] && [ -d "$FE_SRC" ]; then
  FE_NAME="$(basename "$(dirname "$FE_SRC")")"
  echo "  ═══ Frontend ($FE_NAME) ═══"
  echo ""

  FE_TS_COUNT=$(find "$FE_SRC" -name "*.ts" -o -name "*.tsx" | wc -l | tr -d ' ')
  echo "  TypeScript files: $FE_TS_COUNT"

  FE_TEST_COUNT=$(find "$FE_SRC" -name "*.spec.ts" -o -name "*.spec.tsx" -o -name "*.test.ts" -o -name "*.test.tsx" 2>/dev/null | wc -l | tr -d ' ')
  echo "  Test files: $FE_TEST_COUNT"

  # use client directives
  USE_CLIENT=$(grep -rl "\"use client\"" "$FE_SRC" --include="*.tsx" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
  echo "  'use client' components: $USE_CLIENT"

  # any usage
  FE_ANY=$(grep -r ": any\b" "$FE_SRC" --include="*.ts" --include="*.tsx" 2>/dev/null | wc -l | tr -d ' ')
  echo "  'any' type usage: $FE_ANY"

  # console usage
  FE_CONSOLE=$(grep -r "console\.log" "$FE_SRC" --include="*.ts" --include="*.tsx" 2>/dev/null | wc -l | tr -d ' ')
  echo "  console.log usage: $FE_CONSOLE"
else
  echo "  [skip] No frontend source directory detected"
fi

echo ""
echo "  ════════════════════════════════════════════"
echo "  Scan complete."
echo ""

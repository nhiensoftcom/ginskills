#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Dependency & Import Analyzer
#
# Detects circular dependencies, unused exports, orphan files,
# and import boundary violations. Pure bash — no npm deps.
#
# Usage:
#   ./dep-check.sh                    # scan all projects
#   ./dep-check.sh backend            # scan backend only
#   ./dep-check.sh frontend           # scan frontend only
#   ./dep-check.sh mobile             # scan mobile only
#   ./dep-check.sh --check circular   # only circular deps
#   ./dep-check.sh --check unused     # only unused exports
#   ./dep-check.sh --check orphans    # only orphan files
#   ./dep-check.sh --check boundaries # only import boundary violations
#   ./dep-check.sh --summary          # summary counts only
#
# Output: JSON to stdout
# Exit codes: 0 = clean, 1 = issues found, 2 = critical issues
# ─────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────
TARGET="all"
CHECK="all"
SUMMARY_ONLY=false

# ─── Auto-detect project directories ────────────────────────
detect_src() {
  local kind="$1"; shift
  for candidate in "$@"; do
    for dir in $REPO_ROOT/$candidate; do
      if [ -d "$dir/src" ]; then echo "$dir/src"; return; fi
      if [ -d "$dir/app" ]; then echo "$dir/app"; return; fi
    done
  done
  echo ""
}

detect_root() {
  local kind="$1"; shift
  for candidate in "$@"; do
    for dir in $REPO_ROOT/$candidate; do
      if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then echo "$dir"; return; fi
    done
  done
  echo ""
}

BE_SRC="$(detect_src backend be-* backend server api)"
FE_SRC="$(detect_src frontend web-* frontend client)"
MB_SRC="$(detect_src mobile styai-mobile mobile)"
AUTH_SRC=""
[ -d "$REPO_ROOT/auth-package/src" ] && AUTH_SRC="$REPO_ROOT/auth-package/src"

BE_ROOT="$(detect_root backend be-* backend server api)"
FE_ROOT="$(detect_root frontend web-* frontend client)"
MB_ROOT="$(detect_root mobile styai-mobile mobile)"

# ─── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    backend)  TARGET="backend"; shift ;;
    frontend) TARGET="frontend"; shift ;;
    mobile)   TARGET="mobile"; shift ;;
    auth)     TARGET="auth"; shift ;;
    --check)  CHECK="$2"; shift 2 ;;
    --summary) SUMMARY_ONLY=true; shift ;;
    *) shift ;;
  esac
done

# ─── Build file list ────────────────────────────────────────
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

FILES_LIST="$TMPDIR_WORK/files.txt"
FINDINGS_FILE="$TMPDIR_WORK/findings.jsonl"
touch "$FINDINGS_FILE"

build_file_list() {
  local dirs=""
  case "$TARGET" in
    backend)  [ -n "$BE_SRC" ] && dirs="$BE_SRC" ;;
    frontend) [ -n "$FE_SRC" ] && dirs="$FE_SRC" ;;
    mobile)   [ -n "$MB_SRC" ] && dirs="$MB_SRC" ;;
    auth)     [ -n "$AUTH_SRC" ] && dirs="$AUTH_SRC" ;;
    all)
      [ -n "$BE_SRC" ] && dirs="$BE_SRC"
      [ -n "$FE_SRC" ] && dirs="$dirs $FE_SRC"
      [ -n "$MB_SRC" ] && dirs="$dirs $MB_SRC"
      [ -n "$AUTH_SRC" ] && dirs="$dirs $AUTH_SRC"
      ;;
  esac
  dirs=$(echo "$dirs" | xargs)
  [ -z "$dirs" ] && return
  for dir in $dirs; do
    find "$dir" \( -name "*.ts" -o -name "*.tsx" \) \
      -not -path "*/node_modules/*" \
      -not -path "*/.next/*" \
      -not -path "*/dist/*" \
      -not -path "*.d.ts" \
      2>/dev/null
  done
}

build_file_list | sort > "$FILES_LIST"
FILE_COUNT=$(wc -l < "$FILES_LIST" | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
  echo '{"scan":"dep-check","findings":[],"summary":{"total":0}}'
  exit 0
fi

# ─── Helpers ────────────────────────────────────────────────
relpath() { echo "${1#$REPO_ROOT/}"; }

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || \
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')"
}

count_matches() {
  local result
  result=$(grep -c "$1" "$2" 2>/dev/null) || true
  echo "${result:-0}"
}

add_finding() {
  local check="$1" severity="$2" rule="$3" file="$4" line="$5" message="$6" suggestion="$7"
  if [ "$CHECK" != "all" ] && [ "$CHECK" != "$check" ]; then return; fi
  echo "{\"check\":\"$check\",\"severity\":\"$severity\",\"rule\":\"$rule\",\"file\":\"$(relpath "$file")\",\"line\":$line,\"message\":$(json_escape "$message"),\"suggestion\":$(json_escape "$suggestion")}" >> "$FINDINGS_FILE"
}

# ═══════════════════════════════════════════════════════════════
# 1. CIRCULAR DEPENDENCY DETECTION
# ═══════════════════════════════════════════════════════════════
check_circular() {
  local import_map="$TMPDIR_WORK/import_map.txt"

  # Build import map: file -> imported_file
  while IFS= read -r file; do
    local dir
    dir=$(dirname "$file")
    # Extract import paths (relative imports only)
    grep -n "^import.*from ['\"]\./" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      # Extract the path
      local import_path
      import_path=$(echo "$content" | sed "s/.*from ['\"]//; s/['\"].*//" )
      [ -z "$import_path" ] && continue

      # Resolve to absolute file path
      local resolved=""
      for ext in "" ".ts" ".tsx" "/index.ts" "/index.tsx"; do
        local candidate="$dir/$import_path$ext"
        candidate=$(cd "$(dirname "$candidate")" 2>/dev/null && echo "$(pwd)/$(basename "$candidate")")
        if [ -f "$candidate" ]; then
          resolved="$candidate"
          break
        fi
      done

      [ -n "$resolved" ] && echo "$(relpath "$file")	$(relpath "$resolved")"
    done
  done < "$FILES_LIST" > "$import_map"

  # Detect cycles: A->B->A (direct circular)
  sort "$import_map" | awk -F'\t' '
    {
      from = $1; to = $2
      edges[from] = edges[from] " " to
      # Check for direct cycle: A imports B AND B imports A
      if (from == to) {
        printf "self\t%s\t%s\n", from, from
      }
    }
    END {
      # Check bidirectional imports
      for (a in edges) {
        n = split(edges[a], targets, " ")
        for (i = 1; i <= n; i++) {
          b = targets[i]
          if (b == "" || b == a) continue
          # Check if b also imports a
          m = split(edges[b], btargets, " ")
          for (j = 1; j <= m; j++) {
            if (btargets[j] == a) {
              # Only print once (alphabetically first)
              if (a < b) {
                printf "mutual\t%s\t%s\n", a, b
              }
            }
          }
        }
      }
    }
  ' | sort -u | while IFS=$'\t' read -r kind file_a file_b; do
    if [ "$kind" = "self" ]; then
      add_finding "circular" "critical" "self_import" "$REPO_ROOT/$file_a" 1 \
        "File imports itself" \
        "Remove the self-referencing import"
    else
      add_finding "circular" "warning" "mutual_import" "$REPO_ROOT/$file_a" 1 \
        "Circular dependency: $file_a <-> $file_b" \
        "Break the cycle by extracting shared logic into a third module, or use dependency inversion"
    fi
  done

  # Detect feature-to-feature cross-imports (NestJS modules importing each other)
  if [ -n "$BE_SRC" ] && [ -d "$BE_SRC/features" ]; then
    grep "features/" "$import_map" 2>/dev/null | awk -F'\t' '
      {
        from = $1; to = $2
        # Extract feature names
        split(from, from_parts, "/")
        split(to, to_parts, "/")
        from_feature = ""; to_feature = ""
        for (i = 1; i <= length(from_parts); i++) {
          if (from_parts[i] == "features" && i < length(from_parts)) { from_feature = from_parts[i+1]; break }
        }
        for (i = 1; i <= length(to_parts); i++) {
          if (to_parts[i] == "features" && i < length(to_parts)) { to_feature = to_parts[i+1]; break }
        }
        if (from_feature != "" && to_feature != "" && from_feature != to_feature) {
          key = from_feature "\t" to_feature
          if (!(key in seen)) {
            seen[key] = 1
            printf "%s\t%s\t%s\n", from_feature, to_feature, from
          }
        }
      }
    ' | while IFS=$'\t' read -r from_feat to_feat file; do
      add_finding "circular" "info" "cross_feature_import" "$REPO_ROOT/$file" 1 \
        "Feature '$from_feat' imports from feature '$to_feat'" \
        "Feature modules should communicate through shared interfaces, not import directly from each other"
    done
  fi
}

# ═══════════════════════════════════════════════════════════════
# 2. UNUSED EXPORTS DETECTION
# ═══════════════════════════════════════════════════════════════
check_unused() {
  local exports_file="$TMPDIR_WORK/exports.txt"
  local imports_file="$TMPDIR_WORK/all_imports.txt"

  # Collect all exported symbols
  while IFS= read -r file; do
    # Named exports: export const/function/class/type/interface/enum NAME
    grep -n "^export " "$file" 2>/dev/null | \
      grep -v "^export default\|^export \*\|^export {" | \
      sed 's/.*export \(const\|let\|var\|function\|class\|type\|interface\|enum\|async function\) //' | \
      sed 's/[^a-zA-Z0-9_].*//' | while read -r name; do
        [ -n "$name" ] && echo "$name	$(relpath "$file")"
      done

    # Re-exports from index files are not counted as "unused"
  done < "$FILES_LIST" > "$exports_file"

  # Collect all import references across all files
  while IFS= read -r file; do
    grep "^import " "$file" 2>/dev/null | \
      sed 's/.*{//; s/}.*//' | tr ',' '\n' | \
      sed 's/[[:space:]]*as[[:space:]].*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | \
      grep -v '^$' | while read -r name; do
        echo "$name"
      done
  done < "$FILES_LIST" | sort -u > "$imports_file"

  # Find exports that are never imported anywhere
  while IFS=$'\t' read -r name file; do
    [ -z "$name" ] && continue
    # Skip common framework exports (decorators, modules, etc.)
    case "$name" in
      Module|Controller|Service|Guard|Pipe|Filter|Interceptor|Gateway) continue ;;
      App*|Main|bootstrap) continue ;;
    esac

    # Check if this export is referenced in any other file
    if ! grep -q "^${name}$" "$imports_file" 2>/dev/null; then
      # Double check: is it used in a dynamic import, decorator, or non-standard way?
      local used
      used=$(grep -rl "\b${name}\b" $(cat "$FILES_LIST") 2>/dev/null | grep -v "^${REPO_ROOT}/${file}$" | head -1)
      if [ -z "$used" ]; then
        local lineno
        lineno=$(grep -n "export.*\b${name}\b" "$REPO_ROOT/$file" 2>/dev/null | head -1 | cut -d: -f1)
        lineno=${lineno:-1}
        add_finding "unused" "info" "unused_export" "$REPO_ROOT/$file" "$lineno" \
          "Exported symbol '$name' is not imported by any other file" \
          "Remove the export keyword if only used internally, or delete if truly unused"
      fi
    fi
  done < "$exports_file"
}

# ═══════════════════════════════════════════════════════════════
# 3. ORPHAN FILE DETECTION
# ═══════════════════════════════════════════════════════════════
check_orphans() {
  # Files that are never imported by any other file (potential dead code)
  local all_imports="$TMPDIR_WORK/all_import_paths.txt"

  # Collect all import targets
  while IFS= read -r file; do
    grep "^import.*from ['\"]" "$file" 2>/dev/null | \
      sed "s/.*from ['\"]//; s/['\"].*//" | while read -r import_path; do
        echo "$import_path"
      done
  done < "$FILES_LIST" | sort -u > "$all_imports"

  # Check each file
  while IFS= read -r file; do
    local rel
    rel=$(relpath "$file")
    local basename_no_ext
    basename_no_ext=$(basename "$file" | sed 's/\.[^.]*$//')

    # Skip entry points and special files
    case "$basename_no_ext" in
      main|index|app|App|layout|page|loading|error|not-found) continue ;;
      *.module|*.spec|*.test|*.config|*.d) continue ;;
      _*) continue ;; # Convention: _ prefix = internal
    esac
    [[ "$file" == *"/index."* ]] && continue
    [[ "$file" == *".module."* ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    [[ "$file" == *".config."* ]] && continue

    # Check if this file is imported by anything
    # Try various import path patterns
    local found=false
    local rel_no_ext
    rel_no_ext=$(echo "$rel" | sed 's/\.[^.]*$//')

    # Check if any import path matches this file
    if grep -qF "$basename_no_ext" "$all_imports" 2>/dev/null; then
      found=true
    fi

    # Also check for directory-relative imports that could point to this file
    if [ "$found" = false ]; then
      local dir_name
      dir_name=$(basename "$(dirname "$file")")
      if grep -qF "$dir_name/$basename_no_ext" "$all_imports" 2>/dev/null; then
        found=true
      fi
    fi

    if [ "$found" = false ]; then
      add_finding "orphans" "info" "orphan_file" "$file" 1 \
        "File '$(basename "$file")' is not imported by any other file" \
        "Verify this file is used (may be dynamically loaded, or could be dead code to remove)"
    fi
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# 4. IMPORT BOUNDARY VIOLATIONS
# ═══════════════════════════════════════════════════════════════
check_boundaries() {
  while IFS= read -r file; do
    local rel
    rel=$(relpath "$file")

    # Rule 1: Don't import from node_modules internals (deep imports)
    grep -n "from '[^']*node_modules" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      add_finding "boundaries" "warning" "node_modules_deep_import" "$file" "$lineno" \
        "Direct import from node_modules path" \
        "Import from the package name, not from node_modules internal path"
    done

    # Rule 2: Don't import from parent project (e.g., mobile importing from backend)
    if [[ "$file" == *"/styai-mobile/"* ]]; then
      grep -n "from '.*be-easycloset\|from '.*web-ui-easycloset" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
        add_finding "boundaries" "critical" "cross_project_import" "$file" "$lineno" \
          "Mobile app imports directly from another project" \
          "Use shared packages (auth-package) or API calls instead of direct imports"
      done
    fi

    if [[ "$file" == *"/web-ui-easycloset/"* ]]; then
      grep -n "from '.*be-easycloset\|from '.*styai-mobile" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
        add_finding "boundaries" "critical" "cross_project_import" "$file" "$lineno" \
          "Frontend imports directly from another project" \
          "Use shared packages or API calls instead of direct imports"
      done
    fi

    # Rule 3: Don't import test utilities in production code
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n "from '.*__tests__\|from '.*\.spec\|from '.*\.test\|from '@testing-library\|from 'jest'" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      add_finding "boundaries" "warning" "test_import_in_prod" "$file" "$lineno" \
        "Test utility imported in production code" \
        "Move test-related code to test files"
    done

    # Rule 4: Don't use relative imports that go too far up (../../../..)
    grep -n "from '\.\./\.\./\.\./\.\." "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      add_finding "boundaries" "info" "deep_relative_import" "$file" "$lineno" \
        "Deep relative import (4+ levels up)" \
        "Use path aliases (@/, @features/, @shared/) instead of deep relative imports"
    done

    # Rule 5: Backend internal imports should use path aliases
    if [[ "$file" == *"/be-easycloset/src/"* ]]; then
      grep -n "from '\.\./\.\./\.\." "$file" 2>/dev/null | \
        grep -v "\.spec\.\|\.test\." | while IFS=: read -r lineno content; do
          add_finding "boundaries" "info" "missing_path_alias" "$file" "$lineno" \
            "Deep relative import — consider using path alias" \
            "Use @features/, @shared/, @core/ path aliases instead of ../../.."
        done
    fi

  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# RUN CHECKS
# ═══════════════════════════════════════════════════════════════

if [ "$CHECK" = "all" ] || [ "$CHECK" = "circular" ]; then
  check_circular
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "unused" ]; then
  check_unused
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "orphans" ]; then
  check_orphans
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "boundaries" ]; then
  check_boundaries
fi

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

TOTAL=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
CRITICAL=$(count_matches '"severity":"critical"' "$FINDINGS_FILE")
WARNINGS=$(count_matches '"severity":"warning"' "$FINDINGS_FILE")
INFO=$(count_matches '"severity":"info"' "$FINDINGS_FILE")

CIRCULAR_COUNT=$(count_matches '"check":"circular"' "$FINDINGS_FILE")
UNUSED_COUNT=$(count_matches '"check":"unused"' "$FINDINGS_FILE")
ORPHAN_COUNT=$(count_matches '"check":"orphans"' "$FINDINGS_FILE")
BOUNDARY_COUNT=$(count_matches '"check":"boundaries"' "$FINDINGS_FILE")

if [ "$SUMMARY_ONLY" = true ]; then
  cat <<EOF
{
  "scan": "dep-check",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "files_scanned": $FILE_COUNT,
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "warning": $WARNINGS,
    "info": $INFO,
    "by_check": {
      "circular": $CIRCULAR_COUNT,
      "unused": $UNUSED_COUNT,
      "orphans": $ORPHAN_COUNT,
      "boundaries": $BOUNDARY_COUNT
    }
  }
}
EOF
else
  {
    echo '{'
    echo '  "scan": "dep-check",'
    echo '  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
    echo '  "target": "'"$TARGET"'",'
    echo '  "files_scanned": '"$FILE_COUNT"','
    echo '  "summary": {'
    echo '    "total": '"$TOTAL"','
    echo '    "critical": '"$CRITICAL"','
    echo '    "warning": '"$WARNINGS"','
    echo '    "info": '"$INFO"','
    echo '    "by_check": {'
    echo '      "circular": '"$CIRCULAR_COUNT"','
    echo '      "unused": '"$UNUSED_COUNT"','
    echo '      "orphans": '"$ORPHAN_COUNT"','
    echo '      "boundaries": '"$BOUNDARY_COUNT"
    echo '    }'
    echo '  },'
    echo '  "findings": ['

    first=true
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [ "$first" = true ]; then
        first=false
      else
        echo ','
      fi
      printf '    %s' "$line"
    done < "$FINDINGS_FILE"

    echo ''
    echo '  ]'
    echo '}'
  }
fi

# ─── Exit code ──────────────────────────────────────────────
if [ "$CRITICAL" -gt 0 ]; then
  exit 2
elif [ "$TOTAL" -gt 0 ]; then
  exit 1
else
  exit 0
fi

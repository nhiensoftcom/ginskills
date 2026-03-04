#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Format & Style Consistency Checker
#
# Detects format/style violations and configuration drift
# across the monorepo. Pure bash — no npm deps needed.
#
# What it checks:
#   - Config drift (ESLint/Prettier/TSConfig inconsistencies)
#   - Import ordering violations
#   - File naming conventions
#   - Consistent code patterns per project
#   - Missing TypeScript strict flags
#
# Usage:
#   ./format-check.sh                    # scan all projects
#   ./format-check.sh backend            # scan backend only
#   ./format-check.sh frontend           # scan frontend only
#   ./format-check.sh mobile             # scan mobile only
#   ./format-check.sh --check configs    # only config drift
#   ./format-check.sh --check imports    # only import ordering
#   ./format-check.sh --check naming     # only file naming
#   ./format-check.sh --check patterns   # only pattern consistency
#   ./format-check.sh --summary          # summary counts only
#
# Output: JSON to stdout
# Exit codes: 0 = clean, 1 = issues found
# ─────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────
TARGET="all"
CHECK="all"
SUMMARY_ONLY=false

# ─── Auto-detect project directories ────────────────────────
detect_root() {
  local kind="$1"; shift
  for candidate in "$@"; do
    for dir in $REPO_ROOT/$candidate; do
      if [ -d "$dir" ] && [ -f "$dir/package.json" ]; then echo "$dir"; return; fi
    done
  done
  echo ""
}

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

BE_ROOT="$(detect_root backend be-* backend server api)"
FE_ROOT="$(detect_root frontend web-* frontend client)"
MB_ROOT="$(detect_root mobile styai-mobile mobile)"
AUTH_ROOT=""
[ -d "$REPO_ROOT/auth-package" ] && AUTH_ROOT="$REPO_ROOT/auth-package"

BE_SRC="$(detect_src backend be-* backend server api)"
FE_SRC="$(detect_src frontend web-* frontend client)"
MB_SRC="$(detect_src mobile styai-mobile mobile)"
AUTH_SRC=""
[ -d "$REPO_ROOT/auth-package/src" ] && AUTH_SRC="$REPO_ROOT/auth-package/src"

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
  local check_type="$1" severity="$2" rule="$3" file="$4" line="$5" message="$6" suggestion="$7"
  if [ "$CHECK" != "all" ] && [ "$CHECK" != "$check_type" ]; then return; fi
  echo "{\"check\":\"$check_type\",\"severity\":\"$severity\",\"rule\":\"$rule\",\"file\":\"$(relpath "$file")\",\"line\":$line,\"message\":$(json_escape "$message"),\"suggestion\":$(json_escape "$suggestion")}" >> "$FINDINGS_FILE"
}

# ═══════════════════════════════════════════════════════════════
# 1. CONFIG DRIFT DETECTION
# ═══════════════════════════════════════════════════════════════
check_configs() {
  local projects=()
  local project_roots=()

  case "$TARGET" in
    backend)  [ -n "$BE_ROOT" ] && projects+=("backend") && project_roots+=("$BE_ROOT") ;;
    frontend) [ -n "$FE_ROOT" ] && projects+=("frontend") && project_roots+=("$FE_ROOT") ;;
    mobile)   [ -n "$MB_ROOT" ] && projects+=("mobile") && project_roots+=("$MB_ROOT") ;;
    auth)     [ -n "$AUTH_ROOT" ] && projects+=("auth") && project_roots+=("$AUTH_ROOT") ;;
    all)
      [ -n "$BE_ROOT" ] && projects+=("backend") && project_roots+=("$BE_ROOT")
      [ -n "$FE_ROOT" ] && projects+=("frontend") && project_roots+=("$FE_ROOT")
      [ -n "$MB_ROOT" ] && projects+=("mobile") && project_roots+=("$MB_ROOT")
      [ -n "$AUTH_ROOT" ] && projects+=("auth") && project_roots+=("$AUTH_ROOT")
      ;;
  esac

  [ ${#projects[@]} -eq 0 ] && return

  # ─── Check ESLint config format consistency ──────────────
  local eslint_formats=""
  for i in "${!projects[@]}"; do
    local root="${project_roots[$i]}"
    local name="${projects[$i]}"
    local format="none"

    if [ -f "$root/eslint.config.mjs" ] || [ -f "$root/eslint.config.js" ]; then
      format="flat"
    elif [ -f "$root/.eslintrc.js" ] || [ -f "$root/.eslintrc.json" ] || [ -f "$root/.eslintrc.yml" ]; then
      format="legacy"
    fi

    eslint_formats="$eslint_formats $name:$format"
  done

  # Check if there's a mix
  local has_flat=false has_legacy=false
  for entry in $eslint_formats; do
    case "$entry" in
      *:flat) has_flat=true ;;
      *:legacy) has_legacy=true ;;
    esac
  done

  if [ "$has_flat" = true ] && [ "$has_legacy" = true ]; then
    add_finding "configs" "warning" "eslint_format_drift" "$REPO_ROOT" 0 \
      "Mixed ESLint config formats: $eslint_formats" \
      "Standardize all projects to ESLint 9 flat config format (eslint.config.mjs)"
  fi

  # ─── Check Prettier config consistency ───────────────────
  local quote_styles=""
  local semi_styles=""
  local width_styles=""

  for i in "${!projects[@]}"; do
    local root="${project_roots[$i]}"
    local name="${projects[$i]}"

    for prettier_file in "$root/.prettierrc" "$root/.prettierrc.json" "$root/.prettierrc.js"; do
      if [ -f "$prettier_file" ]; then
        # Extract singleQuote
        local sq
        sq=$(grep -o '"singleQuote"[[:space:]]*:[[:space:]]*\(true\|false\)' "$prettier_file" 2>/dev/null | \
          grep -o 'true\|false' | head -1)
        sq=${sq:-"default"}
        # Also check JS format
        [ "$sq" = "default" ] && sq=$(grep -o "singleQuote[[:space:]]*:[[:space:]]*\(true\|false\)" "$prettier_file" 2>/dev/null | \
          grep -o 'true\|false' | head -1)
        sq=${sq:-"default"}
        quote_styles="$quote_styles $name:$sq"

        # Extract semi
        local semi
        semi=$(grep -o '"semi"[[:space:]]*:[[:space:]]*\(true\|false\)' "$prettier_file" 2>/dev/null | \
          grep -o 'true\|false' | head -1)
        [ -z "$semi" ] && semi=$(grep -o "semi[[:space:]]*:[[:space:]]*\(true\|false\)" "$prettier_file" 2>/dev/null | \
          grep -o 'true\|false' | head -1)
        semi=${semi:-"default"}
        semi_styles="$semi_styles $name:$semi"

        # Extract printWidth
        local pw
        pw=$(grep -oE '"printWidth"[[:space:]]*:[[:space:]]*[0-9]+' "$prettier_file" 2>/dev/null | \
          grep -oE '[0-9]+' | head -1)
        [ -z "$pw" ] && pw=$(grep -oE 'printWidth[[:space:]]*:[[:space:]]*[0-9]+' "$prettier_file" 2>/dev/null | \
          grep -oE '[0-9]+' | head -1)
        pw=${pw:-"default"}
        width_styles="$width_styles $name:$pw"
        break
      fi
    done
  done

  # Check for inconsistencies
  local unique_quotes
  unique_quotes=$(echo "$quote_styles" | tr ' ' '\n' | grep -v '^$' | cut -d: -f2 | sort -u | wc -l | tr -d ' ')
  if [ "$unique_quotes" -gt 1 ]; then
    add_finding "configs" "warning" "prettier_quote_drift" "$REPO_ROOT" 0 \
      "Inconsistent Prettier quote style:$quote_styles" \
      "Standardize singleQuote setting across all projects"
  fi

  local unique_semi
  unique_semi=$(echo "$semi_styles" | tr ' ' '\n' | grep -v '^$' | cut -d: -f2 | sort -u | wc -l | tr -d ' ')
  if [ "$unique_semi" -gt 1 ]; then
    add_finding "configs" "info" "prettier_semi_drift" "$REPO_ROOT" 0 \
      "Inconsistent Prettier semicolon style:$semi_styles" \
      "Consider standardizing semi setting across all projects"
  fi

  local unique_widths
  unique_widths=$(echo "$width_styles" | tr ' ' '\n' | grep -v '^$' | cut -d: -f2 | sort -u | wc -l | tr -d ' ')
  if [ "$unique_widths" -gt 1 ]; then
    add_finding "configs" "info" "prettier_width_drift" "$REPO_ROOT" 0 \
      "Inconsistent Prettier printWidth:$width_styles" \
      "Consider standardizing printWidth across all projects"
  fi

  # ─── Check TypeScript strictness ─────────────────────────
  for i in "${!projects[@]}"; do
    local root="${project_roots[$i]}"
    local name="${projects[$i]}"
    local tsconfig="$root/tsconfig.json"

    [ ! -f "$tsconfig" ] && continue

    # Check for strict: false or missing strict
    local has_strict
    has_strict=$(grep '"strict"' "$tsconfig" 2>/dev/null | grep -o 'true\|false' | head -1)
    has_strict=${has_strict:-"missing"}

    if [ "$has_strict" = "false" ] || [ "$has_strict" = "missing" ]; then
      add_finding "configs" "warning" "ts_not_strict" "$tsconfig" 1 \
        "TypeScript strict mode is $has_strict in $name" \
        "Enable \"strict\": true in tsconfig.json for better type safety"
    fi

    # Check for noImplicitAny: false (explicit unsafe opt-out)
    if grep -q '"noImplicitAny"[[:space:]]*:[[:space:]]*false' "$tsconfig" 2>/dev/null; then
      add_finding "configs" "warning" "ts_no_implicit_any_disabled" "$tsconfig" 1 \
        "noImplicitAny explicitly disabled in $name" \
        "Enable noImplicitAny to catch missing type annotations"
    fi

    # Check strictNullChecks: false
    if grep -q '"strictNullChecks"[[:space:]]*:[[:space:]]*false' "$tsconfig" 2>/dev/null; then
      add_finding "configs" "warning" "ts_strict_null_disabled" "$tsconfig" 1 \
        "strictNullChecks explicitly disabled in $name" \
        "Enable strictNullChecks to prevent null/undefined errors at compile time"
    fi
  done

  # ─── Check for missing configs ───────────────────────────
  for i in "${!projects[@]}"; do
    local root="${project_roots[$i]}"
    local name="${projects[$i]}"

    # Check for .prettierignore
    if [ ! -f "$root/.prettierignore" ]; then
      add_finding "configs" "info" "missing_prettierignore" "$root" 0 \
        "No .prettierignore in $name" \
        "Add .prettierignore to exclude dist/, node_modules/, coverage/ from formatting"
    fi

    # Check for .editorconfig
    if [ ! -f "$root/.editorconfig" ] && [ ! -f "$REPO_ROOT/.editorconfig" ]; then
      add_finding "configs" "info" "missing_editorconfig" "$root" 0 \
        "No .editorconfig in $name or repo root" \
        "Add .editorconfig to enforce consistent indentation across IDEs"
    fi
  done
}

# ═══════════════════════════════════════════════════════════════
# 2. IMPORT ORDERING VIOLATIONS
# ═══════════════════════════════════════════════════════════════
check_imports() {
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue

    # Check for unsorted imports: external imports should come before relative imports
    awk -v fname="$file" '
      /^import.*from/ {
        if ($0 ~ /from ["\047]\./) {
          # Relative import
          if (had_relative == 0) first_relative = NR
          had_relative = 1
        } else {
          # External import
          if (had_relative) {
            # External after relative = wrong order
            printf "%s\t%d\n", fname, NR
          }
        }
      }
      /^[^import]/ && !/^$/ && !/^\/\// { had_relative = 0 }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | sort -u -t$'\t' -k1,1 | head -30 | while IFS=$'\t' read -r file line; do
    add_finding "imports" "info" "import_order" "$file" "$line" \
      "External import after relative import — inconsistent ordering" \
      "Group imports: 1) external packages, 2) path aliases (@/), 3) relative imports (./)"
  done

  # Check for wildcard imports (import * as) which hurt tree-shaking
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n "import \* as" "$file" 2>/dev/null | head -3 | while IFS=: read -r line content; do
      add_finding "imports" "info" "wildcard_import" "$file" "$line" \
        "Wildcard import (import * as) — prevents tree-shaking" \
        "Use named imports instead: import { specific } from '...'"
    done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# 3. FILE NAMING CONVENTIONS
# ═══════════════════════════════════════════════════════════════
check_naming() {
  while IFS= read -r file; do
    local basename
    basename=$(basename "$file")

    # Check for camelCase files (should be kebab-case in most conventions)
    if echo "$basename" | grep -qE '^[a-z]+[A-Z]' 2>/dev/null; then
      # Skip common exceptions
      case "$basename" in
        *.module.ts|*.service.ts|*.controller.ts|*.dto.ts|*.entity.ts) ;; # NestJS convention
        useQuery*|use[A-Z]*) ;; # React hooks
        *)
          add_finding "naming" "info" "camelcase_filename" "$file" 1 \
            "File uses camelCase naming: $basename" \
            "Use kebab-case for file names (e.g., my-component.ts instead of myComponent.ts)"
          ;;
      esac
    fi

    # Check for PascalCase files that aren't React components
    if echo "$basename" | grep -qE '^[A-Z][a-z]+[A-Z]' 2>/dev/null; then
      if [[ "$basename" != *.tsx && "$basename" != *.jsx ]]; then
        # PascalCase non-component files
        case "$basename" in
          *.module.ts|*.guard.ts|*.interceptor.ts|*.filter.ts|*.pipe.ts) ;; # NestJS convention
          *.enum.ts|*.interface.ts|*.type.ts|*.constant.ts|*.config.ts) ;; # Type files
          *)
            add_finding "naming" "info" "pascalcase_non_component" "$file" 1 \
              "Non-component file uses PascalCase: $basename" \
              "Reserve PascalCase for React components (.tsx). Use kebab-case for utilities"
            ;;
        esac
      fi
    fi

    # Check for files with spaces or special characters
    if echo "$basename" | grep -qE '[ ()\[\]!@#$%^&]' 2>/dev/null; then
      add_finding "naming" "warning" "special_chars_filename" "$file" 1 \
        "File name contains special characters: $basename" \
        "Use only alphanumeric characters, hyphens, and dots in file names"
    fi

    # Check for inconsistent test file naming
    if [[ "$basename" == *".test."* ]]; then
      local src_file="${basename/.test/}"
      # Check if there's a matching source file with .spec convention in same project
      local dir
      dir=$(dirname "$file")
      if ls "$dir"/*.spec.* >/dev/null 2>&1; then
        add_finding "naming" "info" "mixed_test_convention" "$file" 1 \
          "Mixed test naming: '$basename' uses .test but sibling files use .spec" \
          "Standardize on one convention (.spec or .test) per project"
      fi
    fi
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# 4. PATTERN CONSISTENCY
# ═══════════════════════════════════════════════════════════════
check_patterns() {
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue

    # Check for mixed export styles in same file
    local has_default has_named
    has_default=$(grep -c "^export default" "$file" 2>/dev/null) || true
    has_named=$(grep -c "^export \(const\|function\|class\|type\|interface\|enum\)" "$file" 2>/dev/null) || true
    has_default=${has_default:-0}
    has_named=${has_named:-0}

    if [ "$has_default" -gt 0 ] && [ "$has_named" -gt 2 ]; then
      add_finding "patterns" "info" "mixed_exports" "$file" 1 \
        "File has both default export and $has_named named exports" \
        "Prefer consistent export style — either all named exports or a single default export"
    fi

    # Check for inconsistent async patterns (mixing .then() with async/await)
    local has_then has_await
    has_then=$(grep -c "\.then(" "$file" 2>/dev/null) || true
    has_await=$(grep -c "await " "$file" 2>/dev/null) || true
    has_then=${has_then:-0}
    has_await=${has_await:-0}

    if [ "$has_then" -gt 2 ] && [ "$has_await" -gt 2 ]; then
      add_finding "patterns" "info" "mixed_async_patterns" "$file" 1 \
        "File mixes .then() ($has_then) and async/await ($has_await) patterns" \
        "Prefer async/await consistently — easier to read and debug"
    fi

    # Check for console.log that should be structured logging (backend only)
    if [[ "$file" == *"/be-"* || "$file" == *"/backend/"* || "$file" == *"/server/"* ]]; then
      local console_count
      console_count=$(grep -c "console\.\(log\|warn\|error\|debug\)" "$file" 2>/dev/null) || true
      console_count=${console_count:-0}
      if [ "$console_count" -gt 3 ]; then
        add_finding "patterns" "warning" "console_over_logger" "$file" 1 \
          "File has $console_count console.* calls — should use structured logger" \
          "Replace console.log with Logger from @nestjs/common or Pino for structured logging"
      fi
    fi

    # Check for string concatenation in template-capable code
    grep -n '+ *["\x27].*["\x27] *+\|["\x27].*["\x27] *+ *[a-zA-Z]' "$file" 2>/dev/null | \
      grep -v "import\|require\|//\|console\.\|\.spec\.\|\.test\." | \
      head -3 | while IFS=: read -r line content; do
        add_finding "patterns" "info" "string_concat" "$file" "$line" \
          "String concatenation — prefer template literals" \
          "Use template literals (\`\${var}\`) instead of string concatenation for readability"
      done

  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# RUN CHECKS
# ═══════════════════════════════════════════════════════════════

if [ "$CHECK" = "all" ] || [ "$CHECK" = "configs" ]; then
  check_configs
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "imports" ]; then
  check_imports
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "naming" ]; then
  check_naming
fi

if [ "$CHECK" = "all" ] || [ "$CHECK" = "patterns" ]; then
  check_patterns
fi

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

TOTAL=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
CRITICAL=$(count_matches '"severity":"critical"' "$FINDINGS_FILE")
WARNINGS=$(count_matches '"severity":"warning"' "$FINDINGS_FILE")
INFO=$(count_matches '"severity":"info"' "$FINDINGS_FILE")

CONFIG_COUNT=$(count_matches '"check":"configs"' "$FINDINGS_FILE")
IMPORT_COUNT=$(count_matches '"check":"imports"' "$FINDINGS_FILE")
NAMING_COUNT=$(count_matches '"check":"naming"' "$FINDINGS_FILE")
PATTERN_COUNT=$(count_matches '"check":"patterns"' "$FINDINGS_FILE")

if [ "$SUMMARY_ONLY" = true ]; then
  cat <<EOF
{
  "scan": "format-check",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "files_scanned": $FILE_COUNT,
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "warning": $WARNINGS,
    "info": $INFO,
    "by_check": {
      "configs": $CONFIG_COUNT,
      "imports": $IMPORT_COUNT,
      "naming": $NAMING_COUNT,
      "patterns": $PATTERN_COUNT
    }
  }
}
EOF
else
  {
    echo '{'
    echo '  "scan": "format-check",'
    echo '  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
    echo '  "target": "'"$TARGET"'",'
    echo '  "files_scanned": '"$FILE_COUNT"','
    echo '  "summary": {'
    echo '    "total": '"$TOTAL"','
    echo '    "critical": '"$CRITICAL"','
    echo '    "warning": '"$WARNINGS"','
    echo '    "info": '"$INFO"','
    echo '    "by_check": {'
    echo '      "configs": '"$CONFIG_COUNT"','
    echo '      "imports": '"$IMPORT_COUNT"','
    echo '      "naming": '"$NAMING_COUNT"','
    echo '      "patterns": '"$PATTERN_COUNT"
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
if [ "$TOTAL" -gt 0 ]; then
  exit 1
else
  exit 0
fi

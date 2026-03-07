#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Coding Standards Checker
#
# Detects constant naming violations, TypeScript typing issues,
# error handling gaps, React/React Native anti-patterns, and
# general conventions. Pure bash + awk — no npm deps needed.
#
# Usage:
#   ./standards-check.sh                          # scan all projects
#   ./standards-check.sh backend                  # scan backend only
#   ./standards-check.sh frontend                 # scan frontend only
#   ./standards-check.sh mobile                   # scan mobile only
#   ./standards-check.sh --category constants     # only constant naming
#   ./standards-check.sh --category typing        # only TS typing issues
#   ./standards-check.sh --category error_handling # only error handling
#   ./standards-check.sh --category react_standards # only React rules
#   ./standards-check.sh --category conventions   # only conventions
#   ./standards-check.sh --severity critical      # only critical issues
#   ./standards-check.sh --summary                # summary counts only
#   ./standards-check.sh --json                   # pure JSON output (default)
#
# Output: JSON to stdout
# Exit codes: 0 = clean, 1 = warnings found, 2 = critical issues
# ─────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────
TARGET="all"
CATEGORY="all"
SEVERITY_FILTER="all"
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
    --category)      CATEGORY="$2"; shift 2 ;;
    --severity)      SEVERITY_FILTER="$2"; shift 2 ;;
    --summary)       SUMMARY_ONLY=true; shift ;;
    --json)          shift ;; # default anyway
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
  echo '{"scan":"standards-check","findings":[],"summary":{"total":0}}'
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
  local category="$1" severity="$2" rule="$3" file="$4" line="$5" message="$6" suggestion="$7"
  # Apply filters
  if [ "$CATEGORY" != "all" ] && [ "$CATEGORY" != "$category" ]; then return; fi
  if [ "$SEVERITY_FILTER" != "all" ] && [ "$SEVERITY_FILTER" != "$severity" ]; then return; fi

  echo "{\"category\":\"$category\",\"severity\":\"$severity\",\"rule\":\"$rule\",\"file\":\"$(relpath "$file")\",\"line\":$line,\"message\":$(json_escape "$message"),\"suggestion\":$(json_escape "$suggestion")}" >> "$FINDINGS_FILE"
}

# ═══════════════════════════════════════════════════════════════
# CONSTANTS — Constant Naming Standards
# ═══════════════════════════════════════════════════════════════

scan_constants() {
  # ─── Top-level consts with primitive literals not UPPER_SNAKE_CASE ──
  # Matches: const foo = 3 / const bar = "str" / const baz = true
  # Skips: destructuring, arrow functions, objects/arrays, imports, React components (PascalCase), hooks (use*)
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '^const [a-zA-Z_][a-zA-Z0-9_]* = ' "$file" 2>/dev/null | \
      grep -E "= (['\"][^'\"]*['\"]|[0-9]+(\.[0-9]+)?|true|false)[[:space:]]*(;|//|$)" | \
      grep -vE "^[0-9]+:[[:space:]]*const [A-Z][A-Z0-9_]*( |=)" | \
      grep -vE "= (import|require)\b" | \
      head -10 | while IFS=: read -r line content; do
        local name
        name=$(echo "$content" | sed 's/const \([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/')
        # Skip: PascalCase (React components), hooks (use*), already UPPER_SNAKE_CASE
        [[ "$name" =~ ^[A-Z][a-z] ]] && continue
        [[ "$name" =~ ^use[A-Z] ]] && continue
        [[ "$name" =~ ^[A-Z][A-Z0-9_]+$ ]] && continue
        add_finding "constants" "warning" "const_not_uppercase" "$file" "$line" \
          "Top-level primitive constant '$name' should be UPPER_SNAKE_CASE" \
          "Rename to $(echo "$name" | sed 's/\([A-Z]\)/_\1/g' | tr '[:lower:]' '[:upper:]' | sed 's/^_//')"
      done
  done < "$FILES_LIST"

  # ─── Enum members not UPPER_SNAKE_CASE or PascalCase ─────
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(const[[:space:]]+)?enum[[:space:]]+/ {
        in_enum = 1; next
      }
      in_enum && /^[[:space:]]*\}/ { in_enum = 0; next }
      in_enum && /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(=|,|$)/ {
        member = $0
        gsub(/^[[:space:]]+/, "", member)
        gsub(/[^a-zA-Z0-9_].*/, "", member)
        if (member == "") next
        # Accept UPPER_SNAKE_CASE or PascalCase — flag everything else
        if (member !~ /^[A-Z][A-Z0-9_]*$/ && member !~ /^[A-Z][a-zA-Z0-9]+$/) {
          printf "%s\t%d\t%s\n", fname, NR, member
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line member; do
    add_finding "constants" "info" "enum_value_not_uppercase" "$file" "$line" \
      "Enum member '$member' should be UPPER_SNAKE_CASE or PascalCase" \
      "Use UPPER_SNAKE_CASE (e.g., ACTIVE_USER) or PascalCase (e.g., ActiveUser) for enum members"
  done

  # ─── Hardcoded numeric literals used in conditions ────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '\bif\b.*[><=!]=\?[[:space:]]*[0-9]\{2,\}\b\|\b[0-9]\{2,\}[[:space:]]*[><=!]=\?' "$file" 2>/dev/null | \
      grep -vE '(import|require|port|PORT|status|Status|0x|0b|\.length|index|version|Version|[0-9]{4}-[0-9]{2})' | \
      grep -vE '//.*[0-9]' | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "constants" "info" "hardcoded_numeric_constant" "$file" "$line" \
          "Numeric literal used directly in condition — should be a named constant" \
          "Extract to a named constant (e.g., const MAX_RETRIES = 3) that explains the value's meaning"
      done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# TYPING — TypeScript Typing Standards
# ═══════════════════════════════════════════════════════════════

scan_typing() {
  # ─── Explicit : any type annotation ──────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n ': any\b' "$file" 2>/dev/null | \
      grep -v 'as any\b' | \
      grep -v '//.*: any' | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "typing" "warning" "explicit_any" "$file" "$line" \
          "Explicit 'any' type annotation weakens TypeScript safety" \
          "Use a specific type, generic, or 'unknown' with type narrowing instead of 'any'"
      done
  done < "$FILES_LIST"

  # ─── Chained type assertions (as unknown as Y) ───────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '\bas [a-zA-Z][a-zA-Z0-9]*\b.*\bas [a-zA-Z]' "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "typing" "warning" "type_assertion_chain" "$file" "$line" \
          "Chained type assertions ('as X as Y') indicate a type escape hatch" \
          "Fix the underlying type mismatch; only use 'as unknown as T' as a last resort"
      done
  done < "$FILES_LIST"

  # ─── Excessive non-null assertion (! operator) ───────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    local count
    count=$(grep -c '!\.' "$file" 2>/dev/null) || true
    count=${count:-0}
    if [ "$count" -gt 3 ]; then
      add_finding "typing" "info" "non_null_assertion" "$file" 1 \
        "File uses non-null assertion (!.) $count times — may hide null reference errors" \
        "Handle nullability explicitly with optional chaining (?.) or null checks"
    fi
  done < "$FILES_LIST"

  # ─── Exported functions without explicit return type ─────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '^export \(async \)\?function [a-zA-Z_][a-zA-Z0-9_]*([^)]*)[^:]*{' "$file" 2>/dev/null | \
      grep -v ': ' | \
      head -5 | while IFS=: read -r line content; do
        local name
        name=$(echo "$content" | sed 's/export \(async \)\?function \([a-zA-Z_][a-zA-Z0-9_]*\).*/\2/')
        add_finding "typing" "info" "implicit_return_type" "$file" "$line" \
          "Exported function '$name' is missing an explicit return type annotation" \
          "Add a return type (e.g., function $name(...): Promise<void>) for clarity and contract enforcement"
      done
  done < "$FILES_LIST"

  # ─── NestJS injectable constructor params without readonly ─
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    [[ "$file" != *".service."* && "$file" != *".controller."* && \
       "$file" != *".gateway."* && "$file" != *".guard."* && \
       "$file" != *".interceptor."* ]] && continue
    grep -n 'constructor(' "$file" 2>/dev/null | head -3 | while IFS=: read -r line _content; do
      # Check the next few lines after constructor for params without readonly
      awk -v start="$line" -v fname="$file" '
        NR >= start && NR <= start + 10 {
          if ($0 ~ /private [^r]/ || $0 ~ /private [a-zA-Z]/ ) {
            if ($0 !~ /readonly/) {
              printf "%s\t%d\n", fname, NR
            }
          }
        }
      ' "$file" 2>/dev/null
    done
  done < "$FILES_LIST" | head -20 | while IFS=$'\t' read -r file line; do
    add_finding "typing" "info" "no_readonly_injection" "$file" "$line" \
      "NestJS injectable constructor parameter is missing 'readonly'" \
      "Add 'readonly' to injected constructor params (e.g., private readonly userService: UserService)"
  done
}

# ═══════════════════════════════════════════════════════════════
# ERROR HANDLING — Error Handling Standards
# ═══════════════════════════════════════════════════════════════

scan_error_handling() {
  # ─── throw "string" instead of throw new Error() ─────────
  while IFS= read -r file; do
    grep -n "throw ['\"][^'\"]*['\"]" "$file" 2>/dev/null | \
      grep -v '//.*throw' | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "error_handling" "critical" "throw_string_literal" "$file" "$line" \
          "Throwing a string literal instead of an Error object" \
          "Use 'throw new Error(\"message\")' — string throws lose stack traces and aren't instanceof Error"
      done
  done < "$FILES_LIST"

  # ─── .then() without .catch() on the same statement ──────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /\.then\(/ && !/\.catch\(/ {
        # Buffer the statement — check if .catch appears before semicolon or next statement
        stmt = $0; stmt_line = NR
        in_stmt = 1
        next
      }
      in_stmt {
        stmt = stmt $0
        if ($0 ~ /\.catch\(/) { in_stmt = 0; next }
        # End of statement: semicolon or start of new statement
        if ($0 ~ /;[[:space:]]*$/ || $0 ~ /^[[:space:]]*[a-zA-Z]/ || $0 ~ /^[[:space:]]*\}/) {
          if (stmt !~ /\.catch\(/) {
            printf "%s\t%d\n", fname, stmt_line
          }
          in_stmt = 0
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -30 | while IFS=$'\t' read -r file line; do
    add_finding "error_handling" "warning" "promise_no_catch" "$file" "$line" \
      ".then() chain without .catch() — unhandled promise rejection" \
      "Add .catch(err => ...) or convert to async/await with try-catch"
  done

  # ─── Exported async functions with await but no try-catch ─
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(public[[:space:]]+)?(async[[:space:]]+)(function[[:space:]]+)?[a-zA-Z_]/ {
        func_start = NR; in_func = 1; brace_depth = 0
        has_await = 0; has_try = 0; func_line = NR
        func_name = $0
        gsub(/^.*async[[:space:]]+/, "", func_name)
        gsub(/[^a-zA-Z0-9_].*/, "", func_name)
        if (func_name == "") func_name = "anonymous"
      }
      in_func {
        if ($0 ~ /\bawait\b/) has_await = 1
        if ($0 ~ /\btry[[:space:]]*\{/) has_try = 1
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (brace_depth <= 0 && NR > func_start) {
          if (has_await && !has_try) {
            printf "%s\t%d\t%s\n", fname, func_line, func_name
          }
          in_func = 0
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -20 | while IFS=$'\t' read -r file line name; do
    add_finding "error_handling" "info" "async_no_try_catch" "$file" "$line" \
      "Exported async function '$name' uses await without try-catch" \
      "Wrap await calls in try-catch or use a centralized error handler / interceptor"
  done

  # ─── Promise.reject() or reject() without Error object ───
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n 'Promise\.reject([^)]*)\|reject([^)]*)' "$file" 2>/dev/null | \
      grep -v 'new Error\|new.*Error\|Promise\.reject()' | \
      grep -v '//.*reject' | \
      head -5 | while IFS=: read -r line content; do
        # Only flag if the argument is a string or identifier (not an Error)
        if echo "$content" | grep -qE "reject\(['\"]|reject\([a-z][a-zA-Z0-9]*\)"; then
          add_finding "error_handling" "warning" "reject_without_error" "$file" "$line" \
            "Promise.reject() called without an Error object" \
            "Use 'Promise.reject(new Error(\"...\"))' to preserve stack traces"
        fi
      done
  done < "$FILES_LIST"

  # ─── catch clause without typing the error ───────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n 'catch[[:space:]]*(e)' "$file" 2>/dev/null | \
      grep -v 'catch[[:space:]]*(e[[:space:]]*:[[:space:]]*(unknown\|Error\|any))' | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "error_handling" "info" "catch_without_type" "$file" "$line" \
          "Catch clause uses untyped error variable 'e'" \
          "Type the catch parameter: catch (e: unknown) and narrow with instanceof Error"
      done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# REACT STANDARDS — React/React Native Standards
# ═══════════════════════════════════════════════════════════════

scan_react_standards() {
  # ─── Inline style={{ ... }} in JSX ───────────────────────
  while IFS= read -r file; do
    [[ "$file" != *".tsx" && "$file" != *".jsx" ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n 'style={{' "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "react_standards" "info" "inline_style_object" "$file" "$line" \
          "Inline style object in JSX — recreated on every render" \
          "Move to StyleSheet.create() (React Native) or a Tailwind className (web)"
      done
  done < "$FILES_LIST"

  # ─── React.forwardRef / React.memo without displayName ───
  while IFS= read -r file; do
    [[ "$file" != *".tsx" && "$file" != *".jsx" ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /React\.(forwardRef|memo)\(/ {
        found_line = NR
        name_on_line = $0
        gsub(/.*=.*React\.(forwardRef|memo)\(.*/, "", name_on_line)
        in_block = 1; check_line = NR
      }
      in_block && /\.displayName[[:space:]]*=/ { in_block = 0 }
      in_block && NR > check_line + 20 {
        printf "%s\t%d\n", fname, found_line
        in_block = 0
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line; do
    add_finding "react_standards" "info" "missing_display_name" "$file" "$line" \
      "React.forwardRef or React.memo component missing displayName" \
      "Add 'ComponentName.displayName = \"ComponentName\"' for better DevTools debugging"
  done

  # ─── Array index used as key in JSX ──────────────────────
  while IFS= read -r file; do
    [[ "$file" != *".tsx" && "$file" != *".jsx" ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n 'key={index}\|key={i}\|key={idx}\|key={_index}' "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "react_standards" "warning" "index_as_key" "$file" "$line" \
          "Array index used as JSX key — causes incorrect reconciliation on reorder/delete" \
          "Use a stable, unique identifier from the data (e.g., key={item.id})"
      done
  done < "$FILES_LIST"

  # ─── Nested ternary in JSX return ────────────────────────
  while IFS= read -r file; do
    [[ "$file" != *".tsx" && "$file" != *".jsx" ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /return[[:space:]]*\(/ { in_return = 1; return_line = NR }
      in_return && /\?.*\?/ {
        # Two ? on the same line indicates a nested ternary
        if ($0 !~ /\/\//) {
          printf "%s\t%d\n", fname, NR
        }
      }
      in_return && /^[[:space:]]*\)[[:space:]]*;?[[:space:]]*$/ { in_return = 0 }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -20 | while IFS=$'\t' read -r file line; do
    add_finding "react_standards" "warning" "nested_ternary_jsx" "$file" "$line" \
      "Nested ternary operator inside JSX return — hard to read" \
      "Extract to a variable, early return, or a separate component before the return statement"
  done

  # ─── Multiline inline arrow functions in JSX props ───────
  while IFS= read -r file; do
    [[ "$file" != *".tsx" && "$file" != *".jsx" ]] && continue
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /={.*=>.*\{[[:space:]]*$/ {
        # Inline arrow that opens a block (multiline)
        printf "%s\t%d\n", fname, NR
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -10 | while IFS=$'\t' read -r file line; do
    add_finding "react_standards" "info" "large_inline_function" "$file" "$line" \
      "Multiline arrow function in JSX prop — recreated on every render" \
      "Extract to a named callback defined outside the JSX, or wrap with useCallback"
  done
}

# ═══════════════════════════════════════════════════════════════
# CONVENTIONS — General Conventions
# ═══════════════════════════════════════════════════════════════

scan_conventions() {
  # ─── Mixed single/double quotes in imports ────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    local single_imports double_imports
    single_imports=$(grep -c "^import.*from '" "$file" 2>/dev/null) || true
    double_imports=$(grep -c '^import.*from "' "$file" 2>/dev/null) || true
    single_imports=${single_imports:-0}
    double_imports=${double_imports:-0}
    if [ "$single_imports" -gt 0 ] && [ "$double_imports" -gt 0 ]; then
      add_finding "conventions" "info" "inconsistent_quotes" "$file" 1 \
        "File mixes single ($single_imports) and double ($double_imports) quotes in import statements" \
        "Standardize on one quote style — configure via Prettier's singleQuote option"
    fi
  done < "$FILES_LIST"

  # ─── Directory with 3+ exported files but no index.ts barrel ─
  # Collect directories that have multiple .ts files with exports
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    dirname "$file"
  done < "$FILES_LIST" | sort | uniq -c | awk '$1 >= 3 { print $2 }' | \
  while IFS= read -r dir; do
    # Check if there's an index.ts or index.tsx barrel
    if [ ! -f "$dir/index.ts" ] && [ ! -f "$dir/index.tsx" ]; then
      # Check if any file in the directory has exports
      local exported_files
      exported_files=$(grep -l '^export ' "$dir"/*.ts "$dir"/*.tsx 2>/dev/null | \
        grep -v '\.spec\.\|\.test\.' | wc -l | tr -d ' ')
      if [ "${exported_files:-0}" -ge 3 ]; then
        add_finding "conventions" "info" "no_barrel_export" "$dir/index.ts" 1 \
          "Directory '$(basename "$dir")' has $exported_files exported files but no index.ts barrel" \
          "Create an index.ts that re-exports public symbols to simplify imports"
      fi
    fi
  done

  # ─── God module: file with more than 10 exports ──────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    local export_count
    export_count=$(grep -c '^export ' "$file" 2>/dev/null) || true
    export_count=${export_count:-0}
    if [ "$export_count" -gt 10 ]; then
      add_finding "conventions" "warning" "max_exports" "$file" 1 \
        "File has $export_count exports — possible god module" \
        "Split into focused modules; each file should have a single, clear responsibility"
    fi
  done < "$FILES_LIST"

  # ─── Switch statement without a default case ─────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    awk -v fname="$file" '
      /^[[:space:]]*switch[[:space:]]*\(/ {
        switch_line = NR; in_switch = 1; brace_depth = 0; has_default = 0
      }
      in_switch {
        if ($0 ~ /\bdefault[[:space:]]*:/) has_default = 1
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (brace_depth < 0) {
          if (!has_default) {
            printf "%s\t%d\n", fname, switch_line
          }
          in_switch = 0
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -20 | while IFS=$'\t' read -r file line; do
    add_finding "conventions" "info" "switch_without_default" "$file" "$line" \
      "Switch statement has no default case" \
      "Add a default case to handle unexpected values explicitly (throw or log a warning)"
  done

  # ─── Nested ternary (non-JSX) ─────────────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '?\s*[^:]*?\s*[^:]*:' "$file" 2>/dev/null | \
      grep -v '//.*?' | \
      grep -v 'return\s*(' | \
      grep -v 'jsx\|JSX\|tsx\|TSX' | \
      head -5 | while IFS=: read -r line content; do
        # Verify it's actually a nested ternary (two ? not in a string/comment)
        local q_count
        q_count=$(echo "$content" | tr -cd '?' | wc -c | tr -d ' ')
        if [ "$q_count" -ge 2 ]; then
          add_finding "conventions" "warning" "nested_ternary" "$file" "$line" \
            "Nested ternary expression — difficult to read and reason about" \
            "Extract conditions to named variables or use if-else / early returns"
        fi
      done
  done < "$FILES_LIST"

  # ─── Method chain longer than 5 dots on a single line ────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '\(\.[a-zA-Z_][a-zA-Z0-9_]*(\?\.\|\.)\)\{5,\}' "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line content; do
        # Count actual dots (method calls)
        local dot_count
        dot_count=$(echo "$content" | tr -cd '.' | wc -c | tr -d ' ')
        if [ "$dot_count" -ge 5 ]; then
          add_finding "conventions" "info" "long_method_chain" "$file" "$line" \
            "Method chain with $dot_count dot-accesses on one line" \
            "Break the chain into named intermediate variables to improve readability and debuggability"
        fi
      done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# RUN SCANNERS
# ═══════════════════════════════════════════════════════════════

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "constants" ]; then
  scan_constants
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "typing" ]; then
  scan_typing
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "error_handling" ]; then
  scan_error_handling
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "react_standards" ]; then
  scan_react_standards
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "conventions" ]; then
  scan_conventions
fi

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

# Safe grep -c wrapper (avoids 0\n0 issue with pipefail + || echo 0)
count_matches() {
  local result
  result=$(grep -c "$1" "$2" 2>/dev/null) || true
  echo "${result:-0}"
}

TOTAL=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
CRITICAL=$(count_matches '"severity":"critical"' "$FINDINGS_FILE")
WARNINGS=$(count_matches '"severity":"warning"' "$FINDINGS_FILE")
INFO=$(count_matches '"severity":"info"' "$FINDINGS_FILE")

# Count by category
CONSTANTS_COUNT=$(count_matches '"category":"constants"' "$FINDINGS_FILE")
TYPING_COUNT=$(count_matches '"category":"typing"' "$FINDINGS_FILE")
ERROR_HANDLING_COUNT=$(count_matches '"category":"error_handling"' "$FINDINGS_FILE")
REACT_COUNT=$(count_matches '"category":"react_standards"' "$FINDINGS_FILE")
CONVENTIONS_COUNT=$(count_matches '"category":"conventions"' "$FINDINGS_FILE")

if [ "$SUMMARY_ONLY" = true ]; then
  cat <<EOF
{
  "scan": "standards-check",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "files_scanned": $FILE_COUNT,
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "warning": $WARNINGS,
    "info": $INFO,
    "by_category": {
      "constants": $CONSTANTS_COUNT,
      "typing": $TYPING_COUNT,
      "error_handling": $ERROR_HANDLING_COUNT,
      "react_standards": $REACT_COUNT,
      "conventions": $CONVENTIONS_COUNT
    }
  }
}
EOF
else
  {
    echo '{'
    echo '  "scan": "standards-check",'
    echo '  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    echo '  "target": "'"$TARGET"'",'
    echo '  "files_scanned": '$FILE_COUNT','
    echo '  "summary": {'
    echo '    "total": '$TOTAL','
    echo '    "critical": '$CRITICAL','
    echo '    "warning": '$WARNINGS','
    echo '    "info": '$INFO','
    echo '    "by_category": {'
    echo '      "constants": '$CONSTANTS_COUNT','
    echo '      "typing": '$TYPING_COUNT','
    echo '      "error_handling": '$ERROR_HANDLING_COUNT','
    echo '      "react_standards": '$REACT_COUNT','
    echo '      "conventions": '$CONVENTIONS_COUNT
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
elif [ "$WARNINGS" -gt 0 ] || [ "$INFO" -gt 0 ]; then
  exit 1
else
  exit 0
fi

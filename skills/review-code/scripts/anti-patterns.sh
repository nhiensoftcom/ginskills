#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Anti-Pattern & Code Smell Detector
#
# Advanced detection of structural anti-patterns beyond what
# deep-scan.sh covers. Focuses on complexity, duplication,
# async misuse, architecture violations, and maintainability.
#
# Usage:
#   ./anti-patterns.sh                          # scan all projects
#   ./anti-patterns.sh backend                  # scan backend only
#   ./anti-patterns.sh frontend                 # scan frontend only
#   ./anti-patterns.sh mobile                   # scan mobile only
#   ./anti-patterns.sh auth                     # scan auth-package only
#   ./anti-patterns.sh --category complexity    # only complexity checks
#   ./anti-patterns.sh --category duplication   # only duplication checks
#   ./anti-patterns.sh --category promise_patterns
#   ./anti-patterns.sh --category architecture
#   ./anti-patterns.sh --category maintainability
#   ./anti-patterns.sh --severity critical      # only critical findings
#   ./anti-patterns.sh --severity warning
#   ./anti-patterns.sh --severity info
#   ./anti-patterns.sh --summary                # counts only
#   ./anti-patterns.sh --json                   # JSON output (default)
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
FILES_NO_TEST="$TMPDIR_WORK/files_no_test.txt"
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
      [ -n "$BE_SRC" ]   && dirs="$BE_SRC"
      [ -n "$FE_SRC" ]   && dirs="$dirs $FE_SRC"
      [ -n "$MB_SRC" ]   && dirs="$dirs $MB_SRC"
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
grep -v '\.spec\.\|\.test\.' "$FILES_LIST" > "$FILES_NO_TEST" 2>/dev/null || true

FILE_COUNT=$(wc -l < "$FILES_LIST" | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
  echo '{"scan":"anti-patterns","findings":[],"summary":{"total":0}}'
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
# COMPLEXITY
# ═══════════════════════════════════════════════════════════════

scan_complexity() {
  # ─── nested_callbacks: callback hell (function/arrow inside function/arrow inside function/arrow) ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      {
        line = $0
        # Count levels of nested function( or => { patterns on the same line or accumulate
        # Heuristic: count occurrences of "function(" or "=>" per line; 3+ on a single line
        # is very likely callback hell
        count = 0
        s = line
        while (match(s, /function[[:space:]]*\(|=>[[:space:]]*\{/)) {
          count++
          s = substr(s, RSTART + RLENGTH)
        }
        if (count >= 3) {
          printf "%s\t%d\n", fname, NR
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "complexity" "warning" "nested_callbacks" "$file" "$line" \
      "Possible callback hell: 3+ nested function/arrow definitions on one line" \
      "Flatten with async/await or extract nested callbacks into named functions"
  done

  # ─── complex_conditional: boolean expression with more than 3 &&/|| operators ───
  while IFS= read -r file; do
    grep -n '&&\|||' "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      # Count total logical operators on the line
      op_count=$(echo "$content" | grep -o '&&\|||' | wc -l | tr -d ' ')
      if [ "$op_count" -gt 3 ]; then
        echo "$file	$lineno	$op_count"
      fi
    done
  done < "$FILES_NO_TEST" | head -50 | while IFS=$'\t' read -r file line ops; do
    add_finding "complexity" "warning" "complex_conditional" "$file" "$line" \
      "Boolean expression with $ops logical operators (&&/||) in a single condition" \
      "Extract sub-conditions into named boolean variables or helper functions"
  done

  # ─── switch_many_cases: switch with more than 10 cases ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*switch[[:space:]]*\(/ {
        in_switch = 1; case_count = 0; switch_line = NR; brace_depth = 0
      }
      in_switch {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/^[[:space:]]*case[[:space:]]/) case_count++
        if (brace_depth <= 0 && NR > switch_line) {
          if (case_count > 10) printf "%s\t%d\t%d\n", fname, switch_line, case_count
          in_switch = 0
        }
      }
    ' "$file" 2>/dev/null | head -3
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line cases; do
    add_finding "complexity" "info" "switch_many_cases" "$file" "$line" \
      "Switch statement has $cases cases (threshold: 10)" \
      "Consider a lookup map/object or strategy pattern to reduce switch complexity"
  done

  # ─── large_object_literal: object literal with more than 15 properties ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /[=:][[:space:]]*\{[[:space:]]*$/ || /[=:][[:space:]]*\{[a-zA-Z_]/ {
        in_obj = 1; obj_line = NR; prop_count = 0; brace_depth = 0
      }
      in_obj {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        # Count property definitions: "key:" or "key :" patterns
        s = $0
        while (match(s, /[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*:/)) {
          prop_count++
          s = substr(s, RSTART + RLENGTH)
        }
        if (brace_depth <= 0 && NR > obj_line) {
          if (prop_count > 15) printf "%s\t%d\t%d\n", fname, obj_line, prop_count
          in_obj = 0
        }
      }
    ' "$file" 2>/dev/null | head -3
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line props; do
    add_finding "complexity" "info" "large_object_literal" "$file" "$line" \
      "Object literal with ~$props properties (threshold: 15)" \
      "Break into smaller objects or define a named interface/type with sub-objects"
  done

  # ─── deeply_nested_object: destructuring deeper than 3 levels ───
  while IFS= read -r file; do
    grep -n 'const\s*{.*{.*{.*{' "$file" 2>/dev/null | head -5 | while IFS=: read -r lineno content; do
      add_finding "complexity" "info" "deeply_nested_object" "$file" "$lineno" \
        "Object destructuring nested more than 3 levels deep" \
        "Extract intermediate variables or flatten the destructuring with intermediate assignments"
    done
  done < "$FILES_NO_TEST"
}

# ═══════════════════════════════════════════════════════════════
# DUPLICATION
# ═══════════════════════════════════════════════════════════════

scan_duplication() {
  # ─── duplicate_condition: same condition in consecutive if/else-if branches ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(} *else *)?if[[:space:]]*\(/ {
        # Extract the condition between the first ( and matching )
        line = $0
        sub(/^[[:space:]]*(} *else *)?if[[:space:]]*\(/, "", line)
        sub(/\).*$/, "", line)
        cond = line
        if (cond == prev_cond && cond != "") {
          printf "%s\t%d\t%s\n", fname, NR, cond
        }
        prev_cond = cond
        next
      }
      # Reset on non-if/else lines (allow blank lines between)
      /^[[:space:]]*$/ { next }
      !/^[[:space:]]*(} *else|{[[:space:]]*$)/ { prev_cond = "" }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line cond; do
    add_finding "duplication" "critical" "duplicate_condition" "$file" "$line" \
      "Duplicate condition in consecutive if/else-if: '$cond'" \
      "Remove the duplicate branch or combine the conditions with ||"
  done

  # ─── duplicate_switch_case: duplicate case values in a switch ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*switch[[:space:]]*\(/ {
        in_switch = 1; brace_depth = 0
        delete seen_cases
        switch_line = NR
      }
      in_switch {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/^[[:space:]]*case[[:space:]]/) {
          val = $0
          sub(/^[[:space:]]*case[[:space:]]+/, "", val)
          sub(/:[[:space:]]*$/, "", val)
          gsub(/[[:space:]]/, "", val)
          if (val in seen_cases) {
            printf "%s\t%d\t%s\n", fname, NR, val
          }
          seen_cases[val] = NR
        }
        if (brace_depth <= 0 && NR > switch_line) { in_switch = 0 }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line val; do
    add_finding "duplication" "critical" "duplicate_switch_case" "$file" "$line" \
      "Duplicate case value '$val' in switch statement" \
      "Remove the duplicate case — only the first matching case executes"
  done

  # ─── repeated_magic_string: same string (8+ chars) appears 3+ times in a file ───
  while IFS= read -r file; do
    # Extract all string literals (single and double quoted, 8+ chars)
    grep -oE "'[^']{8,}'|\"[^\"]{8,}\"" "$file" 2>/dev/null | \
      grep -vE "^('|\")(import|require|from |@Module|use client|use server|node_modules)" | \
      sort | uniq -c | sort -rn | while read -r cnt str; do
        cnt=$(echo "$cnt" | tr -d ' ')
        if [ "$cnt" -ge 3 ]; then
          lineno=$(grep -nF "$str" "$file" 2>/dev/null | head -1 | cut -d: -f1)
          lineno=${lineno:-1}
          echo "$file	$lineno	$cnt	$str"
        fi
      done
  done < "$FILES_NO_TEST" | head -30 | while IFS=$'\t' read -r file line cnt str; do
    add_finding "duplication" "warning" "repeated_magic_string" "$file" "$line" \
      "String literal $str appears $cnt times in this file" \
      "Extract to a named constant at the top of the file or in a shared constants module"
  done

  # ─── copy_paste_code: 3+ identical consecutive lines appearing elsewhere in the same file ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      {
        # Store lines, skip blank/comment/import lines
        line = $0
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        if (line == "" || line ~ /^\/\// || line ~ /^import /) {
          buf[NR] = ""
          next
        }
        buf[NR] = line
        all_lines[line]++
      }
      END {
        # Slide a 3-line window and look for blocks that appear 2+ times
        for (i = 1; i <= NR - 2; i++) {
          a = buf[i]; b = buf[i+1]; c = buf[i+2]
          if (a == "" || b == "" || c == "") continue
          key = a "\x01" b "\x01" c
          if (key in seen_blocks) {
            if (seen_blocks[key] < i) {  # report only once per block
              printf "%s\t%d\n", fname, i
              seen_blocks[key] = NR + 1  # suppress further reports for this block
            }
          } else {
            seen_blocks[key] = i
          }
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "duplication" "warning" "copy_paste_code" "$file" "$line" \
      "3+ consecutive identical lines appear elsewhere in this file" \
      "Extract the repeated block into a shared helper function"
  done
}

# ═══════════════════════════════════════════════════════════════
# PROMISE PATTERNS
# ═══════════════════════════════════════════════════════════════

scan_promise_patterns() {
  # ─── floating_promise: async call or .then() without await/return/assignment ───
  while IFS= read -r file; do
    grep -n '^\s*[a-zA-Z_][a-zA-Z0-9_.]*\s*\.\s*then\s*(' "$file" 2>/dev/null | \
      grep -v '^\s*\(return\|const\|let\|var\|await\|void\)' | \
      head -5 | while IFS=: read -r lineno content; do
        add_finding "promise_patterns" "warning" "floating_promise" "$file" "$lineno" \
          "Unhandled .then() call — promise result is not awaited or returned" \
          "Add 'await', 'return', or assign to a variable; or use 'void' to intentionally discard"
      done
  done < "$FILES_NO_TEST"

  # Also catch top-level async function calls without await/return/const
  while IFS= read -r file; do
    grep -n '^\s*[a-zA-Z_][a-zA-Z0-9_.]*\s*(' "$file" 2>/dev/null | \
      grep -v '^\s*\(return\|const\|let\|var\|await\|void\|if\|while\|for\|switch\|throw\|expect\|describe\|it\|test\|//\)' | \
      grep -v '^\s*[A-Z]' | \
      while IFS=: read -r lineno content; do
        # Only flag if the called symbol is known async (ends in Async or matches common patterns)
        if echo "$content" | grep -qE '[a-zA-Z](Async|Service|Repository|\.save|\.create|\.update|\.delete|\.find)\s*\('; then
          echo "$file	$lineno"
        fi
      done
  done < "$FILES_NO_TEST" | head -20 | while IFS=$'\t' read -r file line; do
    add_finding "promise_patterns" "warning" "floating_promise" "$file" "$line" \
      "Async function call result not captured — possible floating promise" \
      "Add 'await', 'return', or assign to a variable; use 'void' if intentional"
  done

  # ─── await_in_loop: await inside for/while/forEach ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(for|while)[[:space:]]*\(/ ||
      /\.forEach[[:space:]]*\(/ {
        in_loop = 1; loop_line = NR; brace_depth = 0
      }
      in_loop {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") { brace_depth--; if (brace_depth <= 0) in_loop = 0 }
        }
        if (/\bawait\b/) {
          printf "%s\t%d\n", fname, NR
          in_loop = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "promise_patterns" "warning" "await_in_loop" "$file" "$line" \
      "await used inside a loop body — sequential async is usually unintentional" \
      "Collect promises and resolve with Promise.all() for concurrent execution"
  done

  # ─── promise_constructor_antipattern: new Promise() wrapping an existing async/promise ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /new[[:space:]]+Promise[[:space:]]*\(/ {
        in_promise = 1; promise_line = NR; brace_depth = 0; found_await = 0; found_then = 0
      }
      in_promise {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/\bawait\b/) found_await = 1
        if (/\.then\s*\(/) found_then = 1
        if (brace_depth <= 0 && NR > promise_line) {
          if (found_await || found_then) {
            printf "%s\t%d\n", fname, promise_line
          }
          in_promise = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "promise_patterns" "info" "promise_constructor_antipattern" "$file" "$line" \
      "new Promise() wraps an existing async function or .then() chain" \
      "Remove the Promise constructor wrapper and use async/await directly"
  done

  # ─── unnecessary_async: function declared async but never uses await ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /\basync\b.*\bfunction\b|\basync\b[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/ {
        in_func = 1; func_line = NR; has_await = 0; brace_depth = 0
      }
      in_func {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/\bawait\b/) has_await = 1
        if (brace_depth <= 0 && NR > func_line) {
          if (!has_await) printf "%s\t%d\n", fname, func_line
          in_func = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "promise_patterns" "info" "unnecessary_async" "$file" "$line" \
      "Function is declared async but contains no await expression" \
      "Remove the async keyword if no await is needed, or add the missing await"
  done

  # ─── mixed_await_then: same function uses both await and .then() ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /\basync\b.*\bfunction\b|\basync\b[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/ {
        in_func = 1; func_line = NR; has_await = 0; has_then = 0; brace_depth = 0
      }
      in_func {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/\bawait\b/) has_await = 1
        if (/\.then[[:space:]]*\(/) has_then = 1
        if (brace_depth <= 0 && NR > func_line) {
          if (has_await && has_then) printf "%s\t%d\n", fname, func_line
          in_func = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line; do
    add_finding "promise_patterns" "info" "mixed_await_then" "$file" "$line" \
      "Function mixes await and .then() in the same body" \
      "Choose one style consistently — prefer async/await for readability"
  done
}

# ═══════════════════════════════════════════════════════════════
# ARCHITECTURE
# ═══════════════════════════════════════════════════════════════

scan_architecture() {
  # ─── circular_string_import: A imports B and B imports A in the same directory ───
  local dir_imports="$TMPDIR_WORK/dir_imports.txt"
  : > "$dir_imports"

  while IFS= read -r file; do
    local dir
    dir=$(dirname "$file")
    # Collect relative imports within the same directory
    grep -n "from ['\"]\./" "$file" 2>/dev/null | while IFS=: read -r lineno content; do
      local import_path
      import_path=$(echo "$content" | sed "s/.*from ['\"]//; s/['\"].*//" )
      # Only same-directory imports (no slash after ./)
      if echo "$import_path" | grep -qE '^\./[^/]+$'; then
        echo "$(relpath "$file")	$(relpath "$dir")/$( echo "$import_path" | sed 's|^\./||' )"
      fi
    done
  done < "$FILES_LIST" > "$dir_imports"

  # Detect bidirectional pairs
  awk -F'\t' '
    {
      from = $1; to = $2
      edges[from][to] = 1
    }
    END {
      for (a in edges) {
        for (b in edges[a]) {
          if (b in edges && a in edges[b]) {
            if (a < b) printf "%s\t%s\n", a, b
          }
        }
      }
    }
  ' "$dir_imports" 2>/dev/null | sort -u | head -10 | while IFS=$'\t' read -r file_a file_b; do
    add_finding "architecture" "warning" "circular_string_import" "$REPO_ROOT/$file_a" 1 \
      "Circular import detected within same directory: $file_a <-> $file_b" \
      "Extract shared logic to a third file, or restructure to break the cycle"
  done

  # ─── feature_envy: function accesses properties of another object 5+ times ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+/ ||
      /^[[:space:]]*(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*[:{]/ {
        if (in_func) {
          # Check previous function
          for (obj in obj_access) {
            if (obj_access[obj] > 4) {
              printf "%s\t%d\t%s\t%d\n", fname, func_line, obj, obj_access[obj]
            }
          }
          delete obj_access
        }
        in_func = 1; func_line = NR; brace_depth = 0
        delete obj_access
        next
      }
      in_func {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        # Count property accesses: word.prop patterns (excluding this., self., common single-use)
        s = $0
        while (match(s, /[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*/)) {
          access = substr(s, RSTART, RLENGTH)
          obj = access
          sub(/\.[^.]*$/, "", obj)
          if (obj != "this" && obj != "self" && obj != "super" && obj != "console" &&
              obj != "Math" && obj != "Object" && obj != "Array" && obj != "JSON" &&
              obj != "process" && obj != "module" && obj != "exports") {
            obj_access[obj]++
          }
          s = substr(s, RSTART + RLENGTH)
        }
        if (brace_depth <= 0 && NR > func_line) {
          for (obj in obj_access) {
            if (obj_access[obj] > 4) {
              printf "%s\t%d\t%s\t%d\n", fname, func_line, obj, obj_access[obj]
            }
          }
          in_func = 0
          delete obj_access
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line obj count; do
    add_finding "architecture" "info" "feature_envy" "$file" "$line" \
      "Function accesses '$obj' properties $count times — possible feature envy" \
      "Move this logic closer to '$obj', or extract into a method on that object/class"
  done

  # ─── god_function: function with more than 5 control-flow statements ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[a-zA-Z_]/ ||
      /^[[:space:]]*(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*\{/ {
        if (in_func && cf_count > 5) {
          printf "%s\t%d\t%d\t%s\n", fname, func_line, cf_count, func_name
        }
        in_func = 1; func_line = NR; cf_count = 0; brace_depth = 0
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/async[[:space:]]+/, "", line)
        sub(/export[[:space:]]+/, "", line)
        sub(/^function[[:space:]]+/, "", line)
        func_name = line
        sub(/[^a-zA-Z0-9_].*/, "", func_name)
        if (func_name == "") func_name = "anonymous"
      }
      in_func {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (/\bif\b|\belse\b|\bswitch\b|\bfor\b|\bwhile\b/) cf_count++
        if (brace_depth <= 0 && NR > func_line) {
          if (cf_count > 5) printf "%s\t%d\t%d\t%s\n", fname, func_line, cf_count, func_name
          in_func = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line count name; do
    add_finding "architecture" "warning" "god_function" "$file" "$line" \
      "Function '$name' has $count control-flow statements (if/else/switch/for/while)" \
      "Break into smaller focused functions — each function should do one thing"
  done

  # ─── shotgun_surgery_indicator: same function/method name in 5+ files ───
  local func_names_file="$TMPDIR_WORK/func_names.txt"
  : > "$func_names_file"

  while IFS= read -r file; do
    grep -oE '(function |async function )[a-zA-Z_][a-zA-Z0-9_]*|^\s+(async\s+)?[a-zA-Z_][a-zA-Z0-9_]+\s*\([^)]*\)\s*[:{]' "$file" 2>/dev/null | \
      sed 's/.*function //; s/[[:space:]].*//' | \
      grep -vE '^(constructor|get|set|if|for|while|switch|return|catch)$' | \
      while read -r fname; do
        [ -n "$fname" ] && echo "$fname"
      done
  done < "$FILES_NO_TEST" | sort | uniq -c | sort -rn | while read -r cnt fname; do
    cnt=$(echo "$cnt" | tr -d ' ')
    if [ "$cnt" -ge 5 ]; then
      echo "$fname	$cnt"
    fi
  done | head -10 >> "$func_names_file"

  while IFS=$'\t' read -r fname cnt; do
    # Find a representative file
    local sample_file
    sample_file=$(grep -rl "\b$fname\b" $(cat "$FILES_NO_TEST") 2>/dev/null | head -1)
    [ -z "$sample_file" ] && continue
    local sample_line
    sample_line=$(grep -n "\b$fname\b" "$sample_file" 2>/dev/null | head -1 | cut -d: -f1)
    sample_line=${sample_line:-1}
    add_finding "architecture" "info" "shotgun_surgery_indicator" "$sample_file" "$sample_line" \
      "Function/method '$fname' exists in $cnt files — potential shotgun surgery smell" \
      "Consider whether this logic should be consolidated in a shared utility or base class"
  done < "$func_names_file"

  # ─── layer_violation: frontend importing from backend paths or vice versa ───
  if [ -n "$BE_SRC" ] && [ -n "$FE_SRC" ]; then
    local be_pattern
    be_pattern=$(basename "$(dirname "$BE_SRC")")
    local fe_pattern
    fe_pattern=$(basename "$(dirname "$FE_SRC")")
    local mb_pattern=""
    [ -n "$MB_SRC" ] && mb_pattern=$(basename "$(dirname "$MB_SRC")")

    # Backend files importing frontend/mobile paths
    while IFS= read -r file; do
      [[ "$file" != *"$be_pattern"* ]] && continue
      grep -n "from ['\"].*/$fe_pattern/\|from ['\"].*/$mb_pattern/" "$file" 2>/dev/null | \
        head -3 | while IFS=: read -r lineno content; do
          add_finding "architecture" "critical" "layer_violation" "$file" "$lineno" \
            "Backend code imports from frontend/mobile path" \
            "Backend must never depend on frontend or mobile code — use shared packages instead"
        done
    done < "$FILES_LIST"

    # Frontend/mobile files importing backend paths
    while IFS= read -r file; do
      [[ "$file" == *"$be_pattern"* ]] && continue
      grep -n "from ['\"].*/$be_pattern/\|from ['\"].*be-[a-z]" "$file" 2>/dev/null | \
        grep -v "node_modules" | \
        head -3 | while IFS=: read -r lineno content; do
          add_finding "architecture" "critical" "layer_violation" "$file" "$lineno" \
            "Frontend/mobile code imports from backend path" \
            "Frontend and mobile must never depend on backend source — use API calls or shared packages"
        done
    done < "$FILES_LIST"
  fi
}

# ═══════════════════════════════════════════════════════════════
# MAINTAINABILITY
# ═══════════════════════════════════════════════════════════════

scan_maintainability() {
  # ─── long_parameter_list_type: interface/type with more than 8 properties ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(interface|type)[[:space:]]+[A-Z][a-zA-Z0-9_]*/ {
        in_type = 1; type_line = NR; prop_count = 0; brace_depth = 0
        type_name = $0
        sub(/.*\b(interface|type)\b[[:space:]]+/, "", type_name)
        sub(/[^a-zA-Z0-9_].*/, "", type_name)
      }
      in_type {
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        # Count property lines: lines with "name:" or "name?:" pattern
        if (/^[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\??\s*:/) prop_count++
        if (brace_depth <= 0 && NR > type_line) {
          if (prop_count > 8) printf "%s\t%d\t%d\t%s\n", fname, type_line, prop_count, type_name
          in_type = 0
        }
      }
    ' "$file" 2>/dev/null | head -5
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line props name; do
    add_finding "maintainability" "info" "long_parameter_list_type" "$file" "$line" \
      "Interface/type '$name' has $props properties (threshold: 8)" \
      "Split into smaller composable types using intersection types or nesting"
  done

  # ─── excessive_comments: comment lines exceed 40% of total lines ───
  while IFS= read -r file; do
    local total_lines
    total_lines=$(wc -l < "$file" | tr -d ' ')
    [ "$total_lines" -lt 20 ] && continue

    local comment_lines
    comment_lines=$(grep -c '^\s*//' "$file" 2>/dev/null) || comment_lines=0

    # Calculate percentage using awk
    local pct
    pct=$(awk "BEGIN { printf \"%d\", ($comment_lines * 100) / $total_lines }" 2>/dev/null)
    if [ "$pct" -gt 40 ]; then
      echo "$file	1	$pct	$comment_lines	$total_lines"
    fi
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line pct cmts total; do
    add_finding "maintainability" "info" "excessive_comments" "$file" "$line" \
      "Comment lines ($cmts) are $pct% of total lines ($total) — exceeds 40% threshold" \
      "Consider whether comments compensate for unclear code — refactor to self-documenting names"
  done

  # ─── dead_code_indicator: exported symbol not imported by any other file ───
  # Sample the first 20 exports for performance
  local exports_sample="$TMPDIR_WORK/exports_sample.txt"
  : > "$exports_sample"

  while IFS= read -r file; do
    grep -n "^export \(const\|function\|class\|async function\|let\|var\)" "$file" 2>/dev/null | \
      grep -v "^export default\|^export \*\|^export {" | while IFS=: read -r lineno content; do
        local sym
        sym=$(echo "$content" | sed 's/export \(async \)\?\(const\|function\|class\|let\|var\) //; s/[^a-zA-Z0-9_].*//')
        [ -n "$sym" ] && echo "$sym	$(relpath "$file")	$lineno"
      done
  done < "$FILES_NO_TEST" | head -20 > "$exports_sample"

  # Build a combined import names list for quick lookup
  local all_import_names="$TMPDIR_WORK/all_import_names.txt"
  while IFS= read -r file; do
    grep "^import " "$file" 2>/dev/null | \
      sed 's/.*{//; s/}.*//' | tr ',' '\n' | \
      sed 's/[[:space:]]*as[[:space:]].*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | \
      grep -v '^$'
  done < "$FILES_LIST" | sort -u > "$all_import_names"

  while IFS=$'\t' read -r sym rel_file lineno; do
    [ -z "$sym" ] && continue
    # Skip common framework symbols that are used without explicit import
    case "$sym" in
      Module|Controller|Service|Guard|Pipe|Filter|Interceptor|Middleware|Gateway|Resolver) continue ;;
      App*|bootstrap|main) continue ;;
    esac

    if ! grep -q "^${sym}$" "$all_import_names" 2>/dev/null; then
      # Secondary check: grep for the symbol name in any other file
      local found_in
      found_in=$(grep -rl "\b${sym}\b" $(cat "$FILES_LIST") 2>/dev/null | \
        grep -v "^$REPO_ROOT/$rel_file$" | head -1)
      if [ -z "$found_in" ]; then
        add_finding "maintainability" "info" "dead_code_indicator" "$REPO_ROOT/$rel_file" "$lineno" \
          "Exported symbol '$sym' is not referenced by any other file in the project" \
          "Remove the export (or the symbol entirely) if it is truly unused"
      fi
    fi
  done < "$exports_sample"

  # ─── inconsistent_error_messages: same error string used in multiple throw/reject ───
  local error_msgs="$TMPDIR_WORK/error_msgs.txt"
  : > "$error_msgs"

  while IFS= read -r file; do
    grep -n 'throw\s\+new\s\|reject\s*(' "$file" 2>/dev/null | \
      grep -oE "'[^']{6,}'|\"[^\"]{6,}\"" | while read -r msg; do
        echo "$msg"
      done
  done < "$FILES_NO_TEST" | sort | uniq -c | sort -rn | while read -r cnt msg; do
    cnt=$(echo "$cnt" | tr -d ' ')
    if [ "$cnt" -ge 2 ]; then
      echo "$msg	$cnt"
    fi
  done | head -10 > "$error_msgs"

  while IFS=$'\t' read -r msg cnt; do
    [ -z "$msg" ] && continue
    # Find a sample file
    local sample_file sample_line
    sample_file=$(grep -rl "$msg" $(cat "$FILES_NO_TEST") 2>/dev/null | head -1)
    [ -z "$sample_file" ] && continue
    sample_line=$(grep -n "$msg" "$sample_file" 2>/dev/null | head -1 | cut -d: -f1)
    sample_line=${sample_line:-1}
    add_finding "maintainability" "info" "inconsistent_error_messages" "$sample_file" "$sample_line" \
      "Error message $msg used in $cnt throw/reject statements" \
      "Extract to a shared error constants file to ensure consistent messaging"
  done < "$error_msgs"

  # ─── deeply_nested_jsx: JSX nesting deeper than 8 levels ───
  while IFS= read -r file; do
    [[ "$file" != *".tsx" ]] && continue
    awk -v fname="$file" '
      {
        # Approximate JSX depth by counting leading spaces / 2
        indent = 0
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == " ") indent++
          else if (c == "\t") indent += 2
          else break
        }
        level = int(indent / 2)
        # Only flag lines that look like JSX open tags
        if (level > 8 && /^[[:space:]]*<[A-Za-z]/) {
          printf "%s\t%d\t%d\n", fname, NR, level
        }
      }
    ' "$file" 2>/dev/null | head -3
  done < "$FILES_NO_TEST" | while IFS=$'\t' read -r file line level; do
    add_finding "maintainability" "info" "deeply_nested_jsx" "$file" "$line" \
      "JSX nesting estimated at $level levels (threshold: 8)" \
      "Extract deeply nested JSX into sub-components to improve readability"
  done
}

# ═══════════════════════════════════════════════════════════════
# RUN SCANNERS
# ═══════════════════════════════════════════════════════════════

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "complexity" ]; then
  scan_complexity
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "duplication" ]; then
  scan_duplication
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "promise_patterns" ]; then
  scan_promise_patterns
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "architecture" ]; then
  scan_architecture
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "maintainability" ]; then
  scan_maintainability
fi

# ═══════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════

TOTAL=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
CRITICAL=$(count_matches '"severity":"critical"' "$FINDINGS_FILE")
WARNINGS=$(count_matches '"severity":"warning"' "$FINDINGS_FILE")
INFO=$(count_matches '"severity":"info"' "$FINDINGS_FILE")

COMPLEXITY_COUNT=$(count_matches '"category":"complexity"' "$FINDINGS_FILE")
DUPLICATION_COUNT=$(count_matches '"category":"duplication"' "$FINDINGS_FILE")
PROMISE_COUNT=$(count_matches '"category":"promise_patterns"' "$FINDINGS_FILE")
ARCHITECTURE_COUNT=$(count_matches '"category":"architecture"' "$FINDINGS_FILE")
MAINTAINABILITY_COUNT=$(count_matches '"category":"maintainability"' "$FINDINGS_FILE")

if [ "$SUMMARY_ONLY" = true ]; then
  cat <<EOF
{
  "scan": "anti-patterns",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "files_scanned": $FILE_COUNT,
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "warning": $WARNINGS,
    "info": $INFO,
    "by_category": {
      "complexity": $COMPLEXITY_COUNT,
      "duplication": $DUPLICATION_COUNT,
      "promise_patterns": $PROMISE_COUNT,
      "architecture": $ARCHITECTURE_COUNT,
      "maintainability": $MAINTAINABILITY_COUNT
    }
  }
}
EOF
else
  {
    echo '{'
    echo '  "scan": "anti-patterns",'
    echo '  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
    echo '  "target": "'"$TARGET"'",'
    echo '  "files_scanned": '"$FILE_COUNT"','
    echo '  "summary": {'
    echo '    "total": '"$TOTAL"','
    echo '    "critical": '"$CRITICAL"','
    echo '    "warning": '"$WARNINGS"','
    echo '    "info": '"$INFO"','
    echo '    "by_category": {'
    echo '      "complexity": '"$COMPLEXITY_COUNT"','
    echo '      "duplication": '"$DUPLICATION_COUNT"','
    echo '      "promise_patterns": '"$PROMISE_COUNT"','
    echo '      "architecture": '"$ARCHITECTURE_COUNT"','
    echo '      "maintainability": '"$MAINTAINABILITY_COUNT"
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

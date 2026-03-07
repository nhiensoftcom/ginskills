#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Deep Code Scanner — Clean Code Violations
#
# Detects code smells, anti-patterns, SOLID violations, and
# bloaters using pure bash + awk. No npm dependencies needed.
#
# Usage:
#   ./deep-scan.sh                        # scan all projects
#   ./deep-scan.sh backend                # scan backend only
#   ./deep-scan.sh frontend               # scan frontend only
#   ./deep-scan.sh mobile                 # scan mobile only
#   ./deep-scan.sh --category bloaters    # only bloater checks
#   ./deep-scan.sh --severity critical    # only critical issues
#   ./deep-scan.sh --json                 # pure JSON output (default)
#   ./deep-scan.sh --summary              # summary counts only
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
MAX_FUNC_LINES=30
MAX_FILE_LINES=300
MAX_PARAMS=3
MAX_NESTING=3
MAX_METHODS=10
MAX_DEPS=5

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
    --max-func-lines) MAX_FUNC_LINES="$2"; shift 2 ;;
    --max-file-lines) MAX_FILE_LINES="$2"; shift 2 ;;
    --max-params)    MAX_PARAMS="$2"; shift 2 ;;
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
  echo '{"scan":"deep-scan","findings":[],"summary":{"total":0}}'
  exit 0
fi

# ─── Helpers ────────────────────────────────────────────────
relpath() { echo "${1#$REPO_ROOT/}"; }

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || \
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')"
}

add_finding() {
  local category="$1" severity="$2" rule="$3" file="$4" line="$5" message="$6" suggestion="$7"
  # Apply filters
  if [ "$CATEGORY" != "all" ] && [ "$CATEGORY" != "$category" ]; then return; fi
  if [ "$SEVERITY_FILTER" != "all" ] && [ "$SEVERITY_FILTER" != "$severity" ]; then return; fi

  echo "{\"category\":\"$category\",\"severity\":\"$severity\",\"rule\":\"$rule\",\"file\":\"$(relpath "$file")\",\"line\":$line,\"message\":$(json_escape "$message"),\"suggestion\":$(json_escape "$suggestion")}" >> "$FINDINGS_FILE"
}

# ═══════════════════════════════════════════════════════════════
# BLOATERS
# ═══════════════════════════════════════════════════════════════

scan_bloaters() {
  # ─── Long files ──────────────────────────────────────────
  while IFS= read -r file; do
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -gt "$MAX_FILE_LINES" ]; then
      add_finding "bloaters" "warning" "long_file" "$file" 1 \
        "File has $lines lines (threshold: $MAX_FILE_LINES)" \
        "Split into smaller modules with focused responsibilities"
    fi
  done < "$FILES_LIST"

  # ─── Long functions ─────────────────────────────────────
  while IFS= read -r file; do
    awk -v max="$MAX_FUNC_LINES" -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+/ ||
      /^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*(async[[:space:]]*)?\(/ ||
      /^[[:space:]]*(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*[:{]/ {
        if (in_func && func_lines > max) {
          printf "%s\t%d\t%d\t%s\n", fname, func_start, func_lines, func_name
        }
        in_func = 1
        func_start = NR
        func_lines = 0
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        gsub(/async[[:space:]]+/, "", line)
        gsub(/export[[:space:]]+/, "", line)
        gsub(/const[[:space:]]+/, "", line)
        sub(/^function[[:space:]]+/, "", line)
        func_name = line
        sub(/[^a-zA-Z0-9_].*/, "", func_name)
        if (func_name == "") func_name = "anonymous"
        brace_depth = 0
      }
      in_func {
        func_lines++
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (brace_depth <= 0 && func_lines > 1) {
          if (func_lines > max) {
            printf "%s\t%d\t%d\t%s\n", fname, func_start, func_lines, func_name
          }
          in_func = 0
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line count name; do
    add_finding "bloaters" "warning" "long_function" "$file" "$line" \
      "Function '$name' has $count lines (threshold: $MAX_FUNC_LINES)" \
      "Break into smaller focused functions with descriptive names"
  done

  # ─── Too many parameters ─────────────────────────────────
  while IFS= read -r file; do
    grep -n '([^)]*,[^)]*,[^)]*,[^)]*' "$file" 2>/dev/null | \
      grep -E '(function |=>|async )' | while IFS=: read -r line content; do
        # Count commas between parens
        local params
        params=$(echo "$content" | sed 's/.*(\(.*\)).*/\1/' | tr -cd ',' | wc -c | tr -d ' ')
        params=$((params + 1))
        if [ "$params" -gt "$MAX_PARAMS" ]; then
          add_finding "bloaters" "info" "too_many_params" "$file" "$line" \
            "Function has $params parameters (threshold: $MAX_PARAMS)" \
            "Use an options/config object parameter instead"
        fi
      done
  done < "$FILES_LIST"

  # ─── Deep nesting ────────────────────────────────────────
  while IFS= read -r file; do
    awk -v max="$MAX_NESTING" -v fname="$file" '
      {
        indent = 0
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          if (c == " ") indent++
          else if (c == "\t") indent += 2
          else break
        }
        # Approximate nesting level (2-space indent)
        level = int(indent / 2)
        if (level > max && $0 ~ /if|for|while|switch|try/) {
          printf "%s\t%d\t%d\n", fname, NR, level
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | head -50 | while IFS=$'\t' read -r file line level; do
    add_finding "bloaters" "warning" "deep_nesting" "$file" "$line" \
      "Nesting level $level (threshold: $MAX_NESTING)" \
      "Use early returns, guard clauses, or extract nested logic into functions"
  done

  # ─── Classes with too many methods ───────────────────────
  while IFS= read -r file; do
    awk -v max="$MAX_METHODS" -v fname="$file" '
      /^[[:space:]]*export[[:space:]]+class[[:space:]]+/ || /^[[:space:]]*class[[:space:]]+/ {
        if (class_name != "" && method_count > max) {
          printf "%s\t%d\t%d\t%s\n", fname, class_start, method_count, class_name
        }
        class_name = $0
        sub(/.*class[[:space:]]+/, "", class_name)
        sub(/[^a-zA-Z0-9_].*/, "", class_name)
        class_start = NR
        method_count = 0
        in_class = 1
      }
      in_class && /^[[:space:]]+(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(/ {
        method_count++
      }
      END {
        if (class_name != "" && method_count > max) {
          printf "%s\t%d\t%d\t%s\n", fname, class_start, method_count, class_name
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line count name; do
    add_finding "bloaters" "warning" "too_many_methods" "$file" "$line" \
      "Class '$name' has $count methods (threshold: $MAX_METHODS)" \
      "Split into smaller focused classes following Single Responsibility Principle"
  done
}

# ═══════════════════════════════════════════════════════════════
# SOLID VIOLATIONS
# ═══════════════════════════════════════════════════════════════

scan_solid() {
  # ─── Fat controllers (DB/business logic in controllers) ──
  while IFS= read -r file; do
    [[ "$file" != *".controller."* ]] && continue
    local relfile
    relfile=$(relpath "$file")

    # Check for direct model/repository usage in controller
    grep -nE '\.(find|findOne|create|update|delete|save|aggregate)\(' "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "solid" "critical" "fat_controller" "$file" "$line" \
          "Controller contains database operations directly" \
          "Move database operations to the service layer — controllers should only validate input and delegate"
      done

    # Check for business logic patterns
    grep -n "if.*&&.*||" "$file" 2>/dev/null | head -3 | while IFS=: read -r line _content; do
      add_finding "solid" "warning" "fat_controller" "$file" "$line" \
        "Controller contains complex business logic" \
        "Extract business logic to the service layer"
    done
  done < "$FILES_LIST"

  # ─── Too many injected dependencies (SRP smell) ──────────
  while IFS= read -r file; do
    [[ "$file" != *".service."* ]] && continue
    local dep_count
    dep_count=$(grep -cE "@Inject|private.*Service|private.*Repository|private readonly" "$file" 2>/dev/null)
    dep_count=${dep_count:-0}
    if [ "$dep_count" -gt "$MAX_DEPS" ]; then
      add_finding "solid" "warning" "too_many_deps" "$file" 1 \
        "Service has $dep_count injected dependencies (threshold: $MAX_DEPS)" \
        "This service may be doing too much — consider splitting responsibilities"
    fi
  done < "$FILES_LIST"

  # ─── Service locator anti-pattern ────────────────────────
  while IFS= read -r file; do
    grep -nE 'moduleRef\.(get|resolve)\(' "$file" 2>/dev/null | \
      while IFS=: read -r line _content; do
        add_finding "solid" "warning" "service_locator" "$file" "$line" \
          "Using moduleRef.get() — service locator anti-pattern" \
          "Use constructor injection instead of runtime service resolution"
      done
  done < "$FILES_LIST"

  # ─── new keyword for service instantiation ───────────────
  while IFS= read -r file; do
    grep -nE 'new .*(Service|Repository|Controller)\(' "$file" 2>/dev/null | \
      grep -v "\.spec\.\|\.test\.\|mock\|Mock\|stub\|Stub" | \
      while IFS=: read -r line content; do
        add_finding "solid" "warning" "dip_violation" "$file" "$line" \
          "Manual instantiation with 'new' instead of dependency injection" \
          "Let the DI container manage service instantiation"
      done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# CODE SMELLS
# ═══════════════════════════════════════════════════════════════

scan_smells() {
  # ─── Empty catch blocks (try-catch only, not .catch() promise chains) ───
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*\} *catch[[:space:]]*\(/ || /^[[:space:]]*catch[[:space:]]*\(/ {
        catch_line = NR; in_catch = 1; next
      }
      in_catch && /^[[:space:]]*\}/ {
        printf "%s\t%d\n", fname, catch_line
        in_catch = 0
      }
      in_catch && /[^[:space:]]/ { in_catch = 0 }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line; do
    add_finding "smells" "critical" "empty_catch" "$file" "$line" \
      "Empty catch block — errors are silently swallowed" \
      "Log the error or re-throw with context. Never silently ignore exceptions"
  done

  # ─── console.log/warn/error in production code ──────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n "console\.\(log\|warn\|error\|debug\|info\)" "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "smells" "warning" "console_usage" "$file" "$line" \
          "console.log/warn/error in production code" \
          "Use a structured logger (e.g., Pino, Winston) instead of console methods"
      done
  done < "$FILES_LIST"

  # ─── Magic numbers ──────────────────────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* || "$file" == *".config."* ]] && continue
    grep -n '[^a-zA-Z0-9_"'"'"'`\.\/\-][-]\?[0-9]\{2,\}[^a-zA-Z0-9_"'"'"'`px%em\.:\/\-]' "$file" 2>/dev/null | \
      grep -v "import\|require\|console\|//\|TODO\|port\|PORT\|0x\|0b\|index\|length\|\[\|enum\|version\|Version" | \
      head -5 | while IFS=: read -r line content; do
        add_finding "smells" "info" "magic_number" "$file" "$line" \
          "Magic number in code — raw numeric literal" \
          "Extract to a named constant that explains the value's meaning"
      done
  done < "$FILES_LIST"

  # ─── Hardcoded URLs, emails, API keys ────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* || "$file" == *".config."* ]] && continue
    # URLs (not localhost, not imports)
    grep -n 'https\?://[a-zA-Z]' "$file" 2>/dev/null | \
      grep -v "localhost\|127\.0\.0\.1\|import\|require\|//.*http\|swagger\|example\.com\|schema\.org\|node_modules" | \
      head -3 | while IFS=: read -r line _content; do
        add_finding "smells" "warning" "hardcoded_url" "$file" "$line" \
          "Hardcoded URL in source code" \
          "Move to environment variable or configuration"
      done

    # Emails
    grep -n '[a-zA-Z0-9._%+-]\+@[a-zA-Z0-9.-]\+\.[a-zA-Z]\{2,\}' "$file" 2>/dev/null | \
      grep -v "import\|require\|@\(Module\|Controller\|Injectable\|Schema\|Prop\|ApiProperty\|nestjs\|angular\|types\)" | \
      grep -v "\.spec\.\|\.test\.\|example\.com\|@example\|@param\|@returns\|@deprecated" | \
      head -3 | while IFS=: read -r line _content; do
        add_finding "smells" "warning" "hardcoded_email" "$file" "$line" \
          "Hardcoded email address in source code" \
          "Move to environment variable or configuration"
      done
  done < "$FILES_LIST"

  # ─── as any type assertions ─────────────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n " as any\b" "$file" 2>/dev/null | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "smells" "warning" "as_any" "$file" "$line" \
          "'as any' type assertion bypasses TypeScript safety" \
          "Use proper typing, generics, or 'as unknown as Type' if truly needed"
      done
  done < "$FILES_LIST"

  # ─── Boolean function parameters ────────────────────────
  while IFS= read -r file; do
    grep -n '([^)]*:[[:space:]]*boolean[^)]*)[[:space:]]*[:{]' "$file" 2>/dev/null | \
      grep -v "\.spec\.\|\.test\.\|\.dto\.\|interface\|type " | \
      head -5 | while IFS=: read -r line _content; do
        add_finding "smells" "info" "boolean_param" "$file" "$line" \
          "Boolean function parameter — callers will pass opaque true/false" \
          "Use an options object or separate functions for clarity"
      done
  done < "$FILES_LIST"

  # ─── TODO/FIXME/HACK without ticket reference ──────────
  while IFS= read -r file; do
    grep -n 'TODO\|FIXME\|HACK\|XXX' "$file" 2>/dev/null | \
      grep -v '#[0-9]\|JIRA\|ticket\|issue\|github\.com\|LINEAR\|ASANA' | \
      head -10 | while IFS=: read -r line content; do
        local tag
        tag=$(echo "$content" | grep -o 'TODO\|FIXME\|HACK\|XXX' | head -1)
        add_finding "smells" "info" "todo_without_ticket" "$file" "$line" \
          "$tag comment without ticket/issue reference" \
          "Add a ticket reference (e.g., TODO #123) or resolve the issue"
      done
  done < "$FILES_LIST"

  # ─── Commented-out code blocks ──────────────────────────
  while IFS= read -r file; do
    awk -v fname="$file" '
      /^[[:space:]]*\/\/[[:space:]]*(import|export|const|let|var|function|class|if|for|while|return|await|async|try|catch)/ {
        if (!in_comment) { start = NR; count = 0 }
        in_comment = 1
        count++
        next
      }
      {
        if (in_comment && count >= 3) {
          printf "%s\t%d\t%d\n", fname, start, count
        }
        in_comment = 0
      }
      END {
        if (in_comment && count >= 3) {
          printf "%s\t%d\t%d\n", fname, start, count
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | while IFS=$'\t' read -r file line count; do
    add_finding "smells" "info" "commented_code" "$file" "$line" \
      "$count consecutive lines of commented-out code" \
      "Delete commented code — use git history to recover if needed"
  done
}

# ═══════════════════════════════════════════════════════════════
# NAMING
# ═══════════════════════════════════════════════════════════════

scan_naming() {
  # ─── Single-letter variables (outside loops) ─────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* ]] && continue
    grep -n '\b\(const\|let\|var\)\s\+[a-zA-Z]\s*[=:;]' "$file" 2>/dev/null | \
      grep -v 'for\s*(\|\.map\|\.filter\|\.reduce\|\.forEach\|=>\|catch' | \
      head -5 | while IFS=: read -r line content; do
        local varname
        varname=$(echo "$content" | sed 's/.*\(const\|let\|var\)\s\+\([a-zA-Z]\)\s*[=:;].*/\2/')
        # Skip i, j, k, _ (common loop/unused vars)
        [[ "$varname" =~ ^[ijk_]$ ]] && continue
        add_finding "naming" "info" "single_letter_var" "$file" "$line" \
          "Single-letter variable '$varname' — not descriptive" \
          "Use a meaningful name that reveals the variable's purpose"
      done
  done < "$FILES_LIST"

  # ─── Generic names ──────────────────────────────────────
  while IFS= read -r file; do
    [[ "$file" == *".spec."* || "$file" == *".test."* || "$file" == *".dto."* ]] && continue
    grep -n '\b\(const\|let\|var\)\s\+\(data\|result\|temp\|info\|item\|obj\|val\|value\|res\|ret\|tmp\)\b' "$file" 2>/dev/null | \
      grep -v 'import\|require\|interface\|type\s' | \
      head -5 | while IFS=: read -r line content; do
        local varname
        varname=$(echo "$content" | grep -o '\b\(data\|result\|temp\|info\|item\|obj\|val\|value\|res\|ret\|tmp\)\b' | head -1)
        add_finding "naming" "info" "generic_name" "$file" "$line" \
          "Generic variable name '$varname' — doesn't reveal intent" \
          "Use a domain-specific name (e.g., 'userData', 'orderResult', 'configValue')"
      done
  done < "$FILES_LIST"
}

# ═══════════════════════════════════════════════════════════════
# RUN SCANNERS
# ═══════════════════════════════════════════════════════════════

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "bloaters" ]; then
  scan_bloaters
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "solid" ]; then
  scan_solid
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "smells" ]; then
  scan_smells
fi

if [ "$CATEGORY" = "all" ] || [ "$CATEGORY" = "naming" ]; then
  scan_naming
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
BLOATER_COUNT=$(count_matches '"category":"bloaters"' "$FINDINGS_FILE")
SOLID_COUNT=$(count_matches '"category":"solid"' "$FINDINGS_FILE")
SMELL_COUNT=$(count_matches '"category":"smells"' "$FINDINGS_FILE")
NAMING_COUNT=$(count_matches '"category":"naming"' "$FINDINGS_FILE")

if [ "$SUMMARY_ONLY" = true ]; then
  cat <<EOF
{
  "scan": "deep-scan",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "files_scanned": $FILE_COUNT,
  "summary": {
    "total": $TOTAL,
    "critical": $CRITICAL,
    "warning": $WARNINGS,
    "info": $INFO,
    "by_category": {
      "bloaters": $BLOATER_COUNT,
      "solid": $SOLID_COUNT,
      "smells": $SMELL_COUNT,
      "naming": $NAMING_COUNT
    }
  }
}
EOF
else
  {
    echo '{'
    echo '  "scan": "deep-scan",'
    echo '  "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    echo '  "target": "'"$TARGET"'",'
    echo '  "files_scanned": '$FILE_COUNT','
    echo '  "summary": {'
    echo '    "total": '$TOTAL','
    echo '    "critical": '$CRITICAL','
    echo '    "warning": '$WARNINGS','
    echo '    "info": '$INFO','
    echo '    "by_category": {'
    echo '      "bloaters": '$BLOATER_COUNT','
    echo '      "solid": '$SOLID_COUNT','
    echo '      "smells": '$SMELL_COUNT','
    echo '      "naming": '$NAMING_COUNT
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

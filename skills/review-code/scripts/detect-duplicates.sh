#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Duplicate Code Detector
#
# Finds DRY violations using pure bash + awk (no npm deps).
# Detects similar files, duplicate string literals, and
# copy-paste import patterns.
#
# Usage:
#   ./detect-duplicates.sh                    # scan all projects
#   ./detect-duplicates.sh backend            # scan backend only
#   ./detect-duplicates.sh frontend           # scan frontend only
#   ./detect-duplicates.sh mobile             # scan mobile only
#   ./detect-duplicates.sh --min-repeats 2    # minimum string repetitions
#
# Output: JSON to stdout
# Exit codes: 0 = clean, 1 = duplicates found
# ─────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Defaults ────────────────────────────────────────────────
MIN_STRING_REPEATS=3
TARGET="all"

# ─── Auto-detect project directories ────────────────────────
detect_dirs() {
  local kind="$1"; shift
  for candidate in "$@"; do
    for dir in $REPO_ROOT/$candidate; do
      if [ -d "$dir/src" ]; then echo "$dir/src"; return; fi
      if [ -d "$dir/app" ]; then echo "$dir/app"; return; fi
    done
  done
  echo ""
}

BE_SRC="$(detect_dirs backend be-* backend server api)"
FE_SRC="$(detect_dirs frontend web-* frontend client)"
MB_SRC="$(detect_dirs mobile styai-mobile mobile)"
AUTH_SRC=""
[ -d "$REPO_ROOT/auth-package/src" ] && AUTH_SRC="$REPO_ROOT/auth-package/src"

# ─── Parse arguments ────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    backend)  TARGET="backend"; shift ;;
    frontend) TARGET="frontend"; shift ;;
    mobile)   TARGET="mobile"; shift ;;
    auth)     TARGET="auth"; shift ;;
    --min-lines) shift 2 ;;
    --min-repeats) MIN_STRING_REPEATS="$2"; shift 2 ;;
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
      -not -path "*/__tests__/*" \
      -not -path "*.spec.*" \
      -not -path "*.test.*" \
      -not -path "*.d.ts" \
      2>/dev/null
  done
}

build_file_list | sort > "$FILES_LIST"
FILE_COUNT=$(wc -l < "$FILES_LIST" | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
  echo '{"scan":"detect-duplicates","findings":[],"summary":{"total":0,"target":"'"$TARGET"'","files_scanned":0}}'
  exit 0
fi

# ─── Helpers ────────────────────────────────────────────────
relpath() { echo "${1#$REPO_ROOT/}"; }

json_escape() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()), end="")' 2>/dev/null || \
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')"
}

# ═══════════════════════════════════════════════════════════════
# 1. DUPLICATE STRING LITERALS
# ═══════════════════════════════════════════════════════════════
detect_duplicate_strings() {
  local strings_file="$TMPDIR_WORK/strings.txt"

  # Extract single-quoted strings (8+ chars) from all files, excluding imports/decorators
  while IFS= read -r file; do
    grep -noE "'[^']{8,}'" "$file" 2>/dev/null | while IFS=: read -r lineno str; do
      echo "$str"
    done
  done < "$FILES_LIST" | \
    grep -vE "^'(import|require|from|@Module|@Controller|@Injectable|@Schema|node_modules)" | \
    sort | uniq -c | sort -rn | head -25 > "$strings_file"

  while read -r count str; do
    count=$(echo "$count" | tr -d ' ')
    [ "$count" -lt "$MIN_STRING_REPEATS" ] && continue

    # Find sample locations
    local locs=""
    local loc_count=0
    while IFS= read -r file; do
      if grep -qF "$str" "$file" 2>/dev/null; then
        local lineno
        lineno=$(grep -nF "$str" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        [ -n "$lineno" ] && {
          [ $loc_count -gt 0 ] && locs="$locs,"
          locs="$locs{\"file\":\"$(relpath "$file")\",\"line\":$lineno}"
          loc_count=$((loc_count + 1))
          [ $loc_count -ge 3 ] && break
        }
      fi
    done < "$FILES_LIST"

    echo "{\"type\":\"duplicate_string\",\"severity\":\"info\",\"count\":$count,\"value\":$(json_escape "$str"),\"locations\":[$locs],\"suggestion\":\"Extract to a named constant in a shared constants file\"}" >> "$FINDINGS_FILE"
  done < "$strings_file"

  # Also check double-quoted strings
  local dstrings_file="$TMPDIR_WORK/dstrings.txt"
  while IFS= read -r file; do
    grep -noE '"[^"]{8,}"' "$file" 2>/dev/null | while IFS=: read -r lineno str; do
      echo "$str"
    done
  done < "$FILES_LIST" | \
    grep -vE '^"(import|require|from |@Module|@Controller|@Injectable|node_modules|use client|use server)' | \
    sort | uniq -c | sort -rn | head -25 > "$dstrings_file"

  while read -r count str; do
    count=$(echo "$count" | tr -d ' ')
    [ "$count" -lt "$MIN_STRING_REPEATS" ] && continue

    local locs=""
    local loc_count=0
    while IFS= read -r file; do
      if grep -qF "$str" "$file" 2>/dev/null; then
        local lineno
        lineno=$(grep -nF "$str" "$file" 2>/dev/null | head -1 | cut -d: -f1)
        [ -n "$lineno" ] && {
          [ $loc_count -gt 0 ] && locs="$locs,"
          locs="$locs{\"file\":\"$(relpath "$file")\",\"line\":$lineno}"
          loc_count=$((loc_count + 1))
          [ $loc_count -ge 3 ] && break
        }
      fi
    done < "$FILES_LIST"

    echo "{\"type\":\"duplicate_string\",\"severity\":\"info\",\"count\":$count,\"value\":$(json_escape "$str"),\"locations\":[$locs],\"suggestion\":\"Extract to a named constant in a shared constants file\"}" >> "$FINDINGS_FILE"
  done < "$dstrings_file"
}

# ═══════════════════════════════════════════════════════════════
# 2. SIMILAR FILES (by content hash)
# ═══════════════════════════════════════════════════════════════
detect_similar_files() {
  local hash_file="$TMPDIR_WORK/file_hashes.txt"

  while IFS= read -r file; do
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')
    [ "$lines" -lt 20 ] && continue

    # Create structural fingerprint: strip comments, names, literals; hash the skeleton
    local hash
    hash=$(sed 's|//.*$||; s|/\*.*\*/||' "$file" | \
      tr -s '[:space:]' ' ' | \
      sed 's/[a-zA-Z_][a-zA-Z0-9_]*/ID/g; s/[0-9][0-9]*/N/g' | \
      sed "s/'[^']*'/S/g; s/\"[^\"]*\"/S/g" | \
      md5 -q 2>/dev/null || echo "skip")
    [ "$hash" = "skip" ] && continue
    echo "$hash	$lines	$(relpath "$file")"
  done < "$FILES_LIST" > "$hash_file"

  # Group files by hash, find groups of 2+
  sort -t$'\t' -k1,1 "$hash_file" | awk -F'\t' '
    {
      if ($1 == prev_hash && $1 != "") {
        if (count == 1) files = prev_file
        files = files "\t" $3
        count++
        flines = $2
      } else {
        if (count >= 2) {
          printf "%d\t%d\t%s\n", count, flines, files
        }
        count = 1
        files = ""
      }
      prev_hash = $1; prev_file = $3; flines = $2
    }
    END {
      if (count >= 2) {
        printf "%d\t%d\t%s\n", count, flines, files
      }
    }
  ' | sort -t$'\t' -k1 -rn | head -15 | while IFS=$'\t' read -r cnt flines rest; do
    local files_json=""
    local first=true
    local IFS=$'\t'
    for f in $rest; do
      [ -z "$f" ] && continue
      [ "$first" = true ] && first=false || files_json="$files_json,"
      files_json="$files_json{\"file\":\"$f\",\"lines\":$flines}"
    done

    echo "{\"type\":\"similar_files\",\"severity\":\"warning\",\"count\":$cnt,\"lines\":$flines,\"files\":[$files_json],\"suggestion\":\"These files have identical structure — consider extracting shared logic into a base class or utility\"}" >> "$FINDINGS_FILE"
  done
}

# ═══════════════════════════════════════════════════════════════
# 3. DUPLICATE IMPORT PATTERNS
# ═══════════════════════════════════════════════════════════════
detect_duplicate_imports() {
  local import_file="$TMPDIR_WORK/import_hashes.txt"

  # For each file, extract import lines, sort them, hash the block
  while IFS= read -r file; do
    local imports
    imports=$(grep '^import ' "$file" 2>/dev/null | sort)
    local import_count
    import_count=$(echo "$imports" | grep -c '^import' 2>/dev/null)
    import_count=${import_count:-0}
    [ "$import_count" -lt 3 ] && continue

    local hash
    hash=$(echo "$imports" | md5 -q 2>/dev/null || echo "skip")
    [ "$hash" = "skip" ] && continue

    local preview
    preview=$(echo "$imports" | head -1)
    echo "$hash	$(relpath "$file")	$preview"
  done < "$FILES_LIST" > "$import_file"

  # Group by hash
  sort -t$'\t' -k1,1 "$import_file" | awk -F'\t' '
    {
      if ($1 == prev_hash && $1 != "") {
        if (count == 1) { files = prev_file; preview = prev_preview }
        files = files "\t" $2
        count++
      } else {
        if (count >= 3) {
          printf "%d\t%s\t%s\n", count, preview, files
        }
        count = 1
      }
      prev_hash = $1; prev_file = $2; prev_preview = $3
    }
    END {
      if (count >= 3) {
        printf "%d\t%s\t%s\n", count, preview, files
      }
    }
  ' | sort -t$'\t' -k1 -rn | head -10 | while IFS=$'\t' read -r cnt preview rest; do
    local files_json=""
    local first=true
    local IFS=$'\t'
    for f in $rest; do
      [ -z "$f" ] && continue
      [ "$first" = true ] && first=false || files_json="$files_json,"
      files_json="$files_json{\"file\":\"$f\"}"
    done

    echo "{\"type\":\"duplicate_imports\",\"severity\":\"info\",\"count\":$cnt,\"preview\":$(json_escape "$preview"),\"files\":[$files_json],\"suggestion\":\"Consider a barrel export (index.ts) to consolidate these shared imports\"}" >> "$FINDINGS_FILE"
  done
}

# ═══════════════════════════════════════════════════════════════
# 4. IDENTICAL FUNCTION BODIES
# ═══════════════════════════════════════════════════════════════
detect_identical_functions() {
  local func_file="$TMPDIR_WORK/func_hashes.txt"

  # For each file, extract function-like blocks and hash their normalized bodies
  while IFS= read -r file; do
    # Use awk to extract function bodies (BSD awk compatible)
    awk -v fname="$file" '
      /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[a-zA-Z_]/ ||
      /^[[:space:]]*(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\([^)]*\)[[:space:]]*\{/ {
        if (capturing && body_lines >= 5) {
          gsub(/[[:space:]]+/, " ", body)
          printf "%s\t%s:%d\t%s\t%d\n", body, fname, start_line, func_name, body_lines
        }
        capturing = 1
        start_line = NR
        body = ""
        body_lines = 0
        brace_depth = 0

        # Extract function name
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/async[[:space:]]+/, "", line)
        sub(/export[[:space:]]+/, "", line)
        if (match(line, /function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)/)) {
          func_name = substr(line, RSTART + 9)
          sub(/[^a-zA-Z0-9_].*/, "", func_name)
        } else {
          func_name = line
          sub(/[^a-zA-Z0-9_].*/, "", func_name)
        }
      }
      capturing {
        body = body $0 "\n"
        body_lines++
        n = split($0, chars, "")
        for (i = 1; i <= n; i++) {
          if (chars[i] == "{") brace_depth++
          if (chars[i] == "}") brace_depth--
        }
        if (brace_depth <= 0 && body_lines > 1) {
          if (body_lines >= 5) {
            gsub(/[[:space:]]+/, " ", body)
            printf "%s\t%s:%d\t%s\t%d\n", body, fname, start_line, func_name, body_lines
          }
          capturing = 0
          body = ""
          body_lines = 0
        }
      }
    ' "$file" 2>/dev/null
  done < "$FILES_LIST" | sort -t$'\t' -k1,1 > "$func_file"

  # Group identical bodies
  awk -F'\t' '
    {
      key = $1; loc = $2; name = $3; lines = $4
      if (key == prev_key && key != "") {
        if (group_count == 1) {
          group_locs = prev_loc
          group_names = prev_name
        }
        group_locs = group_locs "\t" loc
        group_names = group_names "\t" name
        group_count++
        group_lines = lines
      } else {
        if (group_count >= 2) {
          printf "%d\t%d\t%s\t%s\n", group_count, group_lines, group_locs, group_names
        }
        group_count = 1
        group_locs = ""
        group_names = ""
        group_lines = lines
      }
      prev_key = key; prev_loc = loc; prev_name = name
    }
    END {
      if (group_count >= 2) {
        printf "%d\t%d\t%s\t%s\n", group_count, group_lines, group_locs, group_names
      }
    }
  ' "$func_file" | sort -t$'\t' -k1 -rn | head -15 | while IFS=$'\t' read -r cnt lines locs names; do
    local files_json=""
    local first=true
    local saved_ifs="$IFS"
    IFS=$'\t'
    local loc_arr=($locs)
    local name_arr=($names)
    IFS="$saved_ifs"
    for i in "${!loc_arr[@]}"; do
      local loc="${loc_arr[$i]}"
      local name="${name_arr[$i]:-unknown}"
      local f="${loc%%:*}"
      local l="${loc##*:}"
      [ "$first" = true ] && first=false || files_json="$files_json,"
      files_json="$files_json{\"file\":\"$(relpath "$f")\",\"line\":$l,\"function\":\"$name\"}"
    done

    echo "{\"type\":\"identical_function\",\"severity\":\"warning\",\"count\":$cnt,\"lines\":$lines,\"locations\":[$files_json],\"suggestion\":\"These functions have identical bodies — extract to a shared utility\"}" >> "$FINDINGS_FILE"
  done
}

# ═══════════════════════════════════════════════════════════════
# RUN ALL DETECTORS
# ═══════════════════════════════════════════════════════════════
detect_duplicate_strings
detect_duplicate_imports
detect_similar_files
detect_identical_functions

# ═══════════════════════════════════════════════════════════════
# OUTPUT JSON
# ═══════════════════════════════════════════════════════════════
FINDING_COUNT=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')

# Count by type
DUP_STRING=$(grep -c '"type":"duplicate_string"' "$FINDINGS_FILE" 2>/dev/null)
DUP_STRING=${DUP_STRING:-0}
SIM_FILES=$(grep -c '"type":"similar_files"' "$FINDINGS_FILE" 2>/dev/null)
SIM_FILES=${SIM_FILES:-0}
DUP_IMPORTS=$(grep -c '"type":"duplicate_imports"' "$FINDINGS_FILE" 2>/dev/null)
DUP_IMPORTS=${DUP_IMPORTS:-0}
ID_FUNCS=$(grep -c '"type":"identical_function"' "$FINDINGS_FILE" 2>/dev/null)
ID_FUNCS=${ID_FUNCS:-0}

{
  echo '{'
  echo '  "scan": "detect-duplicates",'
  echo '  "timestamp": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'",'
  echo '  "target": "'"$TARGET"'",'
  echo '  "files_scanned": '"$FILE_COUNT"','
  echo '  "min_string_repeats": '"$MIN_STRING_REPEATS"','
  echo '  "total_findings": '"$FINDING_COUNT"','
  echo '  "by_type": {'
  echo '    "duplicate_string": '"$DUP_STRING"','
  echo '    "similar_files": '"$SIM_FILES"','
  echo '    "duplicate_imports": '"$DUP_IMPORTS"','
  echo '    "identical_function": '"$ID_FUNCS"
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

# ─── Exit code ──────────────────────────────────────────────
if [ "$FINDING_COUNT" -gt 0 ]; then
  exit 1
else
  exit 0
fi

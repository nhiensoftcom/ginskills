#!/usr/bin/env bash
# =============================================================================
# credential-scanner.sh — Deep Credential & Secret Leak Scanner
# =============================================================================
#
# Performs multi-pass scanning for leaked credentials in a codebase.
# Sources secret-patterns.sh for the patterns database.
#
# Usage:
#   ./credential-scanner.sh [directory] [options]
#
# Arguments:
#   directory              Directory to scan (default: current directory)
#
# Options:
#   --format json|text|sarif   Output format (default: text)
#   --severity critical|high|medium|low|all
#                              Minimum severity to report (default: all)
#   --category cloud|payment|vcs|ai|...
#                              Filter by category (default: all categories)
#   --output <file>            Write results to file instead of stdout
#   --verbose                  Show progress and debug information
#   --no-git-history           Skip git history scanning
#   --help                     Show this help message
#
# Exit codes:
#   0 — No findings
#   1 — Only LOW/MEDIUM findings
#   2 — HIGH findings found
#   3 — CRITICAL findings found
#
# =============================================================================

set -euo pipefail

# ─── Script identity ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# ─── Source the patterns database ────────────────────────────────────────────
PATTERNS_FILE="$SCRIPT_DIR/secret-patterns.sh"
if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "ERROR: Cannot find secret-patterns.sh at: $PATTERNS_FILE" >&2
  exit 1
fi
# shellcheck source=./secret-patterns.sh
source "$PATTERNS_FILE"

# ─── Color support ───────────────────────────────────────────────────────────
if [[ -t 1 ]] && command -v tput &>/dev/null && tput colors &>/dev/null && [[ "$(tput colors)" -ge 8 ]]; then
  RED='\033[0;31m'
  ORANGE='\033[0;33m'
  YELLOW='\033[1;33m'
  GREEN='\033[0;32m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' ORANGE='' YELLOW='' GREEN='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ─── Defaults ────────────────────────────────────────────────────────────────
SCAN_DIR=""
OUTPUT_FORMAT="text"
FILTER_SEVERITY="all"
FILTER_CATEGORY="all"
OUTPUT_FILE=""
VERBOSE=false
SCAN_GIT_HISTORY=true
GIT_HISTORY_LIMIT=100

# ─── Counters ────────────────────────────────────────────────────────────────
COUNT_CRITICAL=0
COUNT_HIGH=0
COUNT_MEDIUM=0
COUNT_LOW=0

# ─── Findings storage (parallel-safe temp directory) ─────────────────────────
WORK_DIR=""
cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

# =============================================================================
# HELP
# =============================================================================

show_help() {
  cat <<EOF

${BOLD}${CYAN}credential-scanner.sh${RESET} — Deep credential & secret leak scanner

${BOLD}USAGE${RESET}
  $SCRIPT_NAME [directory] [options]

${BOLD}ARGUMENTS${RESET}
  directory              Path to scan (default: current working directory)

${BOLD}OPTIONS${RESET}
  --format text|json|sarif
                         Output format (default: text)
  --severity critical|high|medium|low|all
                         Minimum severity threshold (default: all)
  --category <name>      Restrict scan to one category: cloud, payment, vcs,
                         ai, auth, database, registry, infra, analytics,
                         saas, crypto, communication, generic
                         (default: all categories)
  --output <file>        Write output to file instead of stdout
  --verbose              Show per-pattern progress and debug info
  --no-git-history       Skip scanning git commit history
  --help                 Show this help

${BOLD}EXIT CODES${RESET}
  0   No findings (clean scan)
  1   LOW or MEDIUM findings only
  2   HIGH findings found
  3   CRITICAL findings found

${BOLD}EXAMPLES${RESET}
  # Scan current directory with default text output
  $SCRIPT_NAME

  # Scan a specific project, output JSON, only CRITICAL/HIGH
  $SCRIPT_NAME ./my-project --format json --severity high --output report.json

  # Scan only cloud credentials, skip git history
  $SCRIPT_NAME . --category cloud --no-git-history

  # Verbose scan to understand what patterns matched
  $SCRIPT_NAME . --verbose

EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

parse_args() {
  # First positional arg (if not a flag) is the directory
  if [[ $# -gt 0 && "$1" != --* ]]; then
    SCAN_DIR="$1"
    shift
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --format)
        [[ $# -lt 2 ]] && { echo "ERROR: --format requires an argument" >&2; exit 1; }
        OUTPUT_FORMAT="$2"
        case "$OUTPUT_FORMAT" in
          text|json|sarif) ;;
          *) echo "ERROR: Unknown format '$OUTPUT_FORMAT'. Use: text, json, sarif" >&2; exit 1 ;;
        esac
        shift 2
        ;;
      --severity)
        [[ $# -lt 2 ]] && { echo "ERROR: --severity requires an argument" >&2; exit 1; }
        FILTER_SEVERITY="$(to_lower "$2")"
        case "$FILTER_SEVERITY" in
          critical|high|medium|low|all) ;;
          *) echo "ERROR: Unknown severity '$FILTER_SEVERITY'. Use: critical, high, medium, low, all" >&2; exit 1 ;;
        esac
        shift 2
        ;;
      --category)
        [[ $# -lt 2 ]] && { echo "ERROR: --category requires an argument" >&2; exit 1; }
        FILTER_CATEGORY="$(to_lower "$2")"
        shift 2
        ;;
      --output)
        [[ $# -lt 2 ]] && { echo "ERROR: --output requires an argument" >&2; exit 1; }
        OUTPUT_FILE="$2"
        shift 2
        ;;
      --verbose)
        VERBOSE=true
        shift
        ;;
      --no-git-history)
        SCAN_GIT_HISTORY=false
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument '$1'. Use --help for usage." >&2
        exit 1
        ;;
    esac
  done

  # Resolve scan directory
  if [[ -z "$SCAN_DIR" ]]; then
    SCAN_DIR="$(pwd)"
  fi
  SCAN_DIR="$(cd "$SCAN_DIR" 2>/dev/null && pwd)" || {
    echo "ERROR: Directory not found: $SCAN_DIR" >&2
    exit 1
  }
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Bash 3.2 compatible case conversion (macOS ships bash 3.2)
to_lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }
to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

log_verbose() {
  $VERBOSE && echo -e "${DIM}  [verbose] $*${RESET}" >&2 || true
}

log_info() {
  echo -e "${CYAN}  [scan]${RESET} $*" >&2
}

log_progress() {
  echo -e "${DIM}  ...${RESET} $*" >&2
}

# Check whether a severity passes the filter threshold
severity_passes_filter() {
  local sev
  sev="$(to_upper "$1")"
  case "$FILTER_SEVERITY" in
    all)      return 0 ;;
    low)      return 0 ;;
    medium)   [[ "$sev" == "MEDIUM" || "$sev" == "HIGH" || "$sev" == "CRITICAL" ]] && return 0 || return 1 ;;
    high)     [[ "$sev" == "HIGH" || "$sev" == "CRITICAL" ]] && return 0 || return 1 ;;
    critical) [[ "$sev" == "CRITICAL" ]] && return 0 || return 1 ;;
  esac
}

# Check whether a category passes the filter
category_passes_filter() {
  local cat
  cat="$(to_lower "$1")"
  [[ "$FILTER_CATEGORY" == "all" || "$FILTER_CATEGORY" == "$cat" ]]
}

# Redact a secret: show first 8 chars, then ****, then last 4 chars
redact_secret() {
  local s="$1"
  local len="${#s}"
  if [[ "$len" -le 12 ]]; then
    # Too short to safely redact — show asterisks
    printf '%s' "$(printf '*%.0s' $(seq 1 "$len"))"
  else
    printf '%s****%s' "${s:0:8}" "${s: -4}"
  fi
}

# Build the exclude-path grep pattern from EXCLUDE_PATHS array
build_exclude_grep() {
  local pattern
  pattern=$(printf '%s\n' "${EXCLUDE_PATHS[@]}" | tr '\n' '|' | sed 's/|$//')
  echo "$pattern"
}

# Build --include flags for grep from SCAN_EXTENSIONS
build_include_flags() {
  local flags=()
  for ext in "${SCAN_EXTENSIONS[@]}"; do
    flags+=("--include=*.$ext")
  done
  # Also include extensionless named files and globs
  for name in "${SCAN_FILENAMES[@]}"; do
    flags+=("--include=$name")
  done
  for glob in "${SCAN_FILENAME_GLOBS[@]}"; do
    flags+=("--include=$glob")
  done
  echo "${flags[@]}"
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

check_dependencies() {
  local missing=()

  if ! command -v grep &>/dev/null; then
    missing+=("grep")
  fi

  if ! command -v python3 &>/dev/null; then
    log_info "${ORANGE}Warning: python3 not found — entropy analysis will be skipped${RESET}"
    PYTHON3_AVAILABLE=false
  else
    PYTHON3_AVAILABLE=true
  fi

  if ! command -v git &>/dev/null; then
    log_info "${ORANGE}Warning: git not found — git history scanning will be skipped${RESET}"
    SCAN_GIT_HISTORY=false
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi

  # Check if scan directory is inside a git repo
  IS_GIT_REPO=false
  if $SCAN_GIT_HISTORY && git -C "$SCAN_DIR" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    IS_GIT_REPO=true
    GIT_REPO_ROOT="$(git -C "$SCAN_DIR" rev-parse --show-toplevel)"
  else
    SCAN_GIT_HISTORY=false
    log_verbose "Not a git repository — git history scan disabled"
  fi
}

# =============================================================================
# FINDING STORAGE
# =============================================================================

# Each finding is stored as a tab-separated line in a temp file:
# SEVERITY<TAB>CATEGORY<TAB>NAME<TAB>FILE<TAB>LINE<TAB>MATCH<TAB>DESCRIPTION<TAB>CONTEXT<TAB>ENTROPY<TAB>SOURCE

record_finding() {
  local severity="$1"    # CRITICAL|HIGH|MEDIUM|LOW
  local category="$2"    # cloud|payment|etc.
  local name="$3"        # pattern name
  local file="$4"        # relative file path
  local line="$5"        # line number
  local match="$6"       # matched content (will be redacted in JSON)
  local description="$7" # human-readable name
  local context="$8"     # surrounding context line
  local entropy="${9:-}"  # entropy value or empty
  local source="${10:-file}"  # file|git_history

  # Apply severity filter
  severity_passes_filter "$severity" || return 0

  # Apply category filter
  category_passes_filter "$category" || return 0

  # Sanitize tabs and newlines in content fields (use spaces to avoid breaking TSV)
  # Use printf+tr for bash 3.2 compatibility (no ${var//pattern/replace} with $'\t')
  match=$(printf '%s' "$match" | tr '\t\n\r' '   ')
  context=$(printf '%s' "$context" | tr '\t\n\r' '   ')
  description=$(printf '%s' "$description" | tr '\t\n\r' '   ')
  name=$(printf '%s' "$name" | tr '\t\n\r' '   ')
  file=$(printf '%s' "$file" | tr '\t\n\r' '   ')

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$severity" "$category" "$name" "$file" "$line" \
    "$match" "$description" "$context" "$entropy" "$source" \
    >> "$WORK_DIR/findings.tsv"

  # Update counters in a counter file (parallel-safe via atomic append)
  echo "$severity" >> "$WORK_DIR/severity_counts.txt"
}

# =============================================================================
# FALSE POSITIVE FILTERING
# =============================================================================

# Returns 0 (true) if the line is a false positive and should be suppressed
is_false_positive() {
  local line="$1"
  for fp in "${FALSE_POSITIVE_PATTERNS[@]}"; do
    if echo "$line" | grep -qE "$fp" 2>/dev/null; then
      log_verbose "FP match '$fp': $line"
      return 0
    fi
  done
  return 1
}

# =============================================================================
# ENTROPY ANALYSIS
# =============================================================================

calculate_entropy() {
  local string="$1"
  if ! $PYTHON3_AVAILABLE; then
    echo "0"
    return
  fi
  echo -n "$string" | python3 -c "
import sys, math, collections
data = sys.stdin.read()
if len(data) == 0:
    print('0.00')
    sys.exit()
freq = collections.Counter(data)
entropy = -sum((c/len(data)) * math.log2(c/len(data)) for c in freq.values())
print(f'{entropy:.2f}')
" 2>/dev/null || echo "0.00"
}

entropy_label() {
  local val="$1"
  # Use python3 for float comparison if available, else awk
  if $PYTHON3_AVAILABLE; then
    python3 -c "
v=float('$val')
if v >= 4.5: print('high')
elif v >= 3.5: print('medium')
else: print('low')
" 2>/dev/null || echo "unknown"
  else
    awk -v v="$val" 'BEGIN{
      if (v+0 >= 4.5) print "high"
      else if (v+0 >= 3.5) print "medium"
      else print "low"
    }'
  fi
}

# =============================================================================
# GREP HELPERS
# =============================================================================

# Build a single grep command string with all exclude-path conditions.
# Outputs matched lines to stdout; caller pipes to per-pattern processing.
grep_in_dir() {
  local pattern="$1"
  shift
  # remaining args: --include=* flags

  local exclude_grep
  exclude_grep="$(build_exclude_grep)"

  # We use grep -rn (recursive + line numbers), pipe through exclude filter
  grep -rn -E "$pattern" "$@" "$SCAN_DIR" 2>/dev/null \
    | grep -vE "$exclude_grep" \
    || true
}

# =============================================================================
# PASS 1 — DIRECT PATTERN MATCHING
# =============================================================================

run_pass1() {
  log_info "Pass 1: Direct pattern matching (${#SECRET_PATTERNS[@]} patterns)..."

  local include_flags
  read -ra include_flags <<< "$(build_include_flags)"

  local count=0
  local total="${#SECRET_PATTERNS[@]}"

  for entry in "${SECRET_PATTERNS[@]}"; do
    count=$((count + 1))

    # Parse the pipe-delimited record
    IFS='|' read -r severity category name regex description <<< "$entry"

    # Apply category filter early to avoid unnecessary grep
    category_passes_filter "$category" || continue
    severity_passes_filter "$severity" || continue

    log_verbose "[$count/$total] Testing pattern: $name"
    $VERBOSE && echo -ne "\r${DIM}  Pass 1: $count/$total patterns${RESET}  " >&2

    # Run grep
    while IFS=: read -r filepath lineno matched_line; do
      [[ -z "$filepath" ]] && continue

      # Normalize path to relative
      local rel_path="${filepath#$SCAN_DIR/}"

      # Apply false positive filter
      is_false_positive "$matched_line" && continue

      # Extract the matched segment (the actual secret value)
      local matched_segment
      matched_segment=$(echo "$matched_line" | grep -oE "$regex" 2>/dev/null | head -1 || echo "$matched_line")

      record_finding \
        "$(to_upper "$severity")" \
        "$category" \
        "$name" \
        "$rel_path" \
        "$lineno" \
        "$matched_segment" \
        "$description" \
        "$(echo "$matched_line" | sed 's/^[[:space:]]*//')" \
        "" \
        "file"

    done < <(grep_in_dir "$regex" "${include_flags[@]}")
  done

  $VERBOSE && echo "" >&2
  log_verbose "Pass 1 complete."
}

# =============================================================================
# PASS 2 — CONTEXTUAL PATTERN MATCHING
# =============================================================================

run_pass2() {
  log_info "Pass 2: Contextual pattern matching (${#CONTEXTUAL_PATTERNS[@]} patterns)..."

  local include_flags
  read -ra include_flags <<< "$(build_include_flags)"
  local exclude_grep
  exclude_grep="$(build_exclude_grep)"

  local count=0
  local total="${#CONTEXTUAL_PATTERNS[@]}"

  for entry in "${CONTEXTUAL_PATTERNS[@]}"; do
    count=$((count + 1))

    # Parse record — description may contain |CONTEXT:<hint>
    IFS='|' read -r severity category name regex description_raw <<< "$entry"

    category_passes_filter "$category" || continue
    severity_passes_filter "$severity" || continue

    # Extract context hint from description if present
    local context_keyword=""
    local description="$description_raw"
    if [[ "$description_raw" == *"|CONTEXT:"* ]]; then
      context_keyword="${description_raw##*|CONTEXT:}"
      description="${description_raw%%|CONTEXT:*}"
      description="${description%%|*}"  # strip trailing pipe
    fi

    log_verbose "[$count/$total] Contextual: $name (context: ${context_keyword:-any})"
    $VERBOSE && echo -ne "\r${DIM}  Pass 2: $count/$total patterns${RESET}  " >&2

    while IFS= read -r grep_line; do
      [[ -z "$grep_line" ]] && continue

      # Split file:line:content
      local filepath lineno matched_line
      filepath=$(echo "$grep_line" | cut -d: -f1)
      lineno=$(echo "$grep_line" | cut -d: -f2)
      matched_line=$(echo "$grep_line" | cut -d: -f3-)

      [[ -z "$filepath" || -z "$lineno" ]] && continue

      local rel_path="${filepath#$SCAN_DIR/}"

      # Apply false positive filter
      is_false_positive "$matched_line" && continue

      # Verify context: extract 5 lines before and after the match from the file
      if [[ -n "$context_keyword" ]]; then
        local context_window
        context_window=$(sed -n "$((lineno > 5 ? lineno - 5 : 1)),$((lineno + 5))p" "$filepath" 2>/dev/null || true)
        if ! echo "$context_window" | grep -qiE "$context_keyword" 2>/dev/null; then
          log_verbose "  Skipped (no context '$context_keyword'): $rel_path:$lineno"
          continue
        fi
      fi

      local matched_segment
      matched_segment=$(echo "$matched_line" | grep -oE "$regex" 2>/dev/null | head -1 || echo "$matched_line")

      record_finding \
        "$(to_upper "$severity")" \
        "$category" \
        "$name" \
        "$rel_path" \
        "$lineno" \
        "$matched_segment" \
        "$description" \
        "$(echo "$matched_line" | sed 's/^[[:space:]]*//')" \
        "" \
        "file"

    done < <(grep -rn -E "$regex" "${include_flags[@]}" "$SCAN_DIR" 2>/dev/null \
               | grep -vE "$exclude_grep" \
               || true)
  done

  $VERBOSE && echo "" >&2
  log_verbose "Pass 2 complete."
}

# =============================================================================
# PASS 3 — ENTROPY ANALYSIS
# =============================================================================

run_pass3() {
  if ! $PYTHON3_AVAILABLE; then
    log_info "Pass 3: Entropy analysis skipped (python3 not available)"
    return
  fi

  log_info "Pass 3: Entropy analysis for generic assignments..."

  local include_flags
  read -ra include_flags <<< "$(build_include_flags)"
  local exclude_grep
  exclude_grep="$(build_exclude_grep)"

  # Generic assignment patterns that need entropy validation
  local entropy_patterns=(
    "token[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/=_\-]{16,}['\"]"
    "key[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/=_\-]{16,}['\"]"
    "secret[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9+/=_\-]{16,}['\"]"
    "password[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
    "credential[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
    "passphrase[[:space:]]*[:=][[:space:]]*['\"][^'\"]{8,}['\"]"
  )

  # Thresholds: hex strings need >4.0, base64 strings need >4.5
  local HEX_THRESHOLD="4.0"
  local B64_THRESHOLD="4.5"

  for pattern in "${entropy_patterns[@]}"; do
    while IFS= read -r grep_line; do
      [[ -z "$grep_line" ]] && continue

      local filepath lineno matched_line
      filepath=$(echo "$grep_line" | cut -d: -f1)
      lineno=$(echo "$grep_line" | cut -d: -f2)
      matched_line=$(echo "$grep_line" | cut -d: -f3-)

      [[ -z "$filepath" || -z "$lineno" ]] && continue

      is_false_positive "$matched_line" && continue

      # Extract the value between quotes
      local value
      value=$(echo "$matched_line" | grep -oE "['\"][A-Za-z0-9+/=_\-]{8,}['\"]" 2>/dev/null \
              | head -1 | tr -d "'\"" || true)

      [[ -z "$value" || "${#value}" -lt 8 ]] && continue

      local entropy
      entropy=$(calculate_entropy "$value")

      # Determine if this is hex or base64
      local threshold="$B64_THRESHOLD"
      if echo "$value" | grep -qE "^[0-9a-fA-F]+$" 2>/dev/null; then
        threshold="$HEX_THRESHOLD"
      fi

      # Check entropy threshold using python3
      local passes_threshold
      passes_threshold=$(python3 -c "print('yes' if float('$entropy') > float('$threshold') else 'no')" 2>/dev/null || echo "no")

      if [[ "$passes_threshold" == "yes" ]]; then
        local rel_path="${filepath#$SCAN_DIR/}"
        local elabel
        elabel=$(entropy_label "$entropy")

        record_finding \
          "MEDIUM" \
          "generic" \
          "HIGH_ENTROPY_SECRET" \
          "$rel_path" \
          "$lineno" \
          "$value" \
          "High-entropy string in generic assignment (entropy: $entropy/$elabel)" \
          "$(echo "$matched_line" | sed 's/^[[:space:]]*//')" \
          "$entropy" \
          "file"
      fi

    done < <(grep -rn -E "$pattern" "${include_flags[@]}" "$SCAN_DIR" 2>/dev/null \
               | grep -vE "$exclude_grep" \
               || true)
  done

  log_verbose "Pass 3 complete."
}

# =============================================================================
# PASS 4 — FILE-BASED CHECKS
# =============================================================================

run_pass4() {
  log_info "Pass 4: File-based checks..."

  local exclude_grep
  exclude_grep="$(build_exclude_grep)"

  # ── 4a: .env files not in .gitignore ────────────────────────────────────
  log_verbose "  Checking .env files vs .gitignore..."
  while IFS= read -r env_file; do
    [[ -z "$env_file" ]] && continue
    echo "$env_file" | grep -qE "$exclude_grep" && continue

    local rel_path="${env_file#$SCAN_DIR/}"

    # Determine if this .env is gitignored
    local is_ignored=false
    if $IS_GIT_REPO; then
      if git -C "$SCAN_DIR" check-ignore -q "$env_file" 2>/dev/null; then
        is_ignored=true
      fi
    fi

    if ! $is_ignored; then
      # It's a real .env file that's not gitignored — check if it has actual values
      if grep -qE "^[A-Z_]+=.{3,}" "$env_file" 2>/dev/null; then
        record_finding \
          "HIGH" \
          "generic" \
          "ENV_FILE_NOT_GITIGNORED" \
          "$rel_path" \
          "1" \
          "$rel_path" \
          ".env file with values is not in .gitignore — may be committed" \
          "File: $rel_path" \
          "" \
          "file"
      fi
    fi

    # Also scan content of .env files with our patterns (they may have real keys)
    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      is_false_positive "$line_content" && continue

      for entry in "${SECRET_PATTERNS[@]}"; do
        IFS='|' read -r severity category name regex description <<< "$entry"
        category_passes_filter "$category" || continue
        severity_passes_filter "$severity" || continue

        if echo "$line_content" | grep -qE "$regex" 2>/dev/null; then
          local matched_segment
          matched_segment=$(echo "$line_content" | grep -oE "$regex" 2>/dev/null | head -1 || echo "$line_content")
          record_finding \
            "$(to_upper "$severity")" \
            "$category" \
            "${name}_IN_ENV_FILE" \
            "$rel_path" \
            "$lineno" \
            "$matched_segment" \
            "$description (found in .env file)" \
            "$(echo "$line_content" | sed 's/^[[:space:]]*//')" \
            "" \
            "file"
          break  # one finding per line is enough
        fi
      done
    done < <(grep -n "" "$env_file" 2>/dev/null || true)

  done < <(find "$SCAN_DIR" \( -name ".env" -o -name ".env.*" -o -name "*.env" \) -type f 2>/dev/null)

  # ── 4b: Private key / certificate files ────────────────────────────────
  log_verbose "  Checking for private key files..."
  local key_extensions=("pem" "key" "p12" "pfx" "jks" "keystore" "cer" "crt")
  for ext in "${key_extensions[@]}"; do
    while IFS= read -r keyfile; do
      [[ -z "$keyfile" ]] && continue
      echo "$keyfile" | grep -qE "$exclude_grep" && continue
      local rel_path="${keyfile#$SCAN_DIR/}"
      record_finding \
        "CRITICAL" \
        "crypto" \
        "PRIVATE_KEY_FILE" \
        "$rel_path" \
        "1" \
        "$rel_path" \
        "Private key or certificate file found in repository" \
        "File: $rel_path" \
        "" \
        "file"
    done < <(find "$SCAN_DIR" -name "*.$ext" -type f 2>/dev/null | grep -vE "$exclude_grep" || true)
  done

  # ── 4c: Credential JSON files ───────────────────────────────────────────
  log_verbose "  Checking for credential JSON files..."
  local cred_filenames=("credentials.json" "service-account.json" "keyfile.json" "gcloud.json" "firebase-adminsdk*.json")
  for fname in "${cred_filenames[@]}"; do
    while IFS= read -r credfile; do
      [[ -z "$credfile" ]] && continue
      echo "$credfile" | grep -qE "$exclude_grep" && continue
      local rel_path="${credfile#$SCAN_DIR/}"
      record_finding \
        "CRITICAL" \
        "cloud" \
        "CREDENTIAL_JSON_FILE" \
        "$rel_path" \
        "1" \
        "$rel_path" \
        "Credential JSON file found in repository (likely GCP service account)" \
        "File: $rel_path" \
        "" \
        "file"
    done < <(find "$SCAN_DIR" -name "$fname" -type f 2>/dev/null | grep -vE "$exclude_grep" || true)
  done

  # ── 4d: .npmrc with auth tokens ─────────────────────────────────────────
  log_verbose "  Checking .npmrc files..."
  while IFS= read -r npmrc; do
    [[ -z "$npmrc" ]] && continue
    echo "$npmrc" | grep -qE "$exclude_grep" && continue
    local rel_path="${npmrc#$SCAN_DIR/}"

    if grep -qE "_authToken=|_auth=|//.*:_authToken" "$npmrc" 2>/dev/null; then
      local lineno
      lineno=$(grep -n "_authToken=\|_auth=\|//.*:_authToken" "$npmrc" 2>/dev/null | head -1 | cut -d: -f1 || echo "1")
      local context_line
      context_line=$(grep -E "_authToken=|_auth=" "$npmrc" 2>/dev/null | head -1 || true)

      is_false_positive "$context_line" && continue

      record_finding \
        "CRITICAL" \
        "registry" \
        "NPMRC_AUTH_TOKEN" \
        "$rel_path" \
        "$lineno" \
        "$(echo "$context_line" | grep -oE "_authToken=\S+" | head -1 || echo "_authToken=****")" \
        "npm auth token found in .npmrc" \
        "$context_line" \
        "" \
        "file"
    fi
  done < <(find "$SCAN_DIR" -name ".npmrc" -type f 2>/dev/null)

  # ── 4e: docker-compose.yml with hardcoded passwords ─────────────────────
  log_verbose "  Checking docker-compose files..."
  while IFS= read -r dcfile; do
    [[ -z "$dcfile" ]] && continue
    echo "$dcfile" | grep -qE "$exclude_grep" && continue
    local rel_path="${dcfile#$SCAN_DIR/}"

    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      # Passwords in docker-compose environment: or secrets:
      if echo "$line_content" | grep -qE "(PASSWORD|SECRET|KEY|TOKEN)[[:space:]]*:[[:space:]]*[^$\"\{\}]" 2>/dev/null; then
        is_false_positive "$line_content" && continue
        local matched_part
        matched_part=$(echo "$line_content" | sed 's/^[[:space:]]*//')
        record_finding \
          "HIGH" \
          "generic" \
          "DOCKER_COMPOSE_HARDCODED_SECRET" \
          "$rel_path" \
          "$lineno" \
          "$matched_part" \
          "Hardcoded secret in docker-compose environment variable" \
          "$matched_part" \
          "" \
          "file"
      fi
    done < <(grep -n "" "$dcfile" 2>/dev/null || true)
  done < <(find "$SCAN_DIR" \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "docker-compose.*.yml" -o -name "docker-compose.*.yaml" \) -type f 2>/dev/null)

  # ── 4f: Dockerfile ENV/ARG with secrets ─────────────────────────────────
  log_verbose "  Checking Dockerfiles..."
  while IFS= read -r dockerfile; do
    [[ -z "$dockerfile" ]] && continue
    echo "$dockerfile" | grep -qE "$exclude_grep" && continue
    local rel_path="${dockerfile#$SCAN_DIR/}"

    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      # ENV or ARG that looks like a secret
      if echo "$line_content" | grep -qiE "^(ENV|ARG)[[:space:]]+(PASSWORD|SECRET|TOKEN|KEY|API_KEY)[[:space:]]*[=[:space:]][^$\"\{\}]" 2>/dev/null; then
        is_false_positive "$line_content" && continue
        local matched_part
        matched_part=$(echo "$line_content" | sed 's/^[[:space:]]*//')
        record_finding \
          "HIGH" \
          "generic" \
          "DOCKERFILE_SECRET_IN_ENV" \
          "$rel_path" \
          "$lineno" \
          "$matched_part" \
          "Secret value in Dockerfile ENV/ARG instruction (baked into image layers)" \
          "$matched_part" \
          "" \
          "file"
      fi
    done < <(grep -n "" "$dockerfile" 2>/dev/null || true)
  done < <(find "$SCAN_DIR" -name "Dockerfile*" -type f 2>/dev/null | grep -vE "$exclude_grep" || true)

  # ── 4g: CI/CD configuration files ───────────────────────────────────────
  log_verbose "  Checking CI/CD configuration files..."

  # GitHub Actions workflows
  while IFS= read -r workflow; do
    [[ -z "$workflow" ]] && continue
    echo "$workflow" | grep -qE "$exclude_grep" && continue
    local rel_path="${workflow#$SCAN_DIR/}"

    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      # Check for env vars with hardcoded values (not using ${{ secrets.* }})
      if echo "$line_content" | grep -qiE "(PASSWORD|SECRET|TOKEN|KEY|API_KEY)[[:space:]]*:[[:space:]]*[^\$\"\{\}]" 2>/dev/null; then
        # Ensure it's not a ${{ secrets.* }} reference
        if ! echo "$line_content" | grep -qE "\\\$\{\{.*secrets\." 2>/dev/null; then
          is_false_positive "$line_content" && continue
          local matched_part
          matched_part=$(echo "$line_content" | sed 's/^[[:space:]]*//')
          record_finding \
            "CRITICAL" \
            "vcs" \
            "CI_HARDCODED_SECRET" \
            "$rel_path" \
            "$lineno" \
            "$matched_part" \
            "Potential hardcoded secret in CI/CD workflow (use secrets context instead)" \
            "$matched_part" \
            "" \
            "file"
        fi
      fi
    done < <(grep -n "" "$workflow" 2>/dev/null || true)
  done < <(find "$SCAN_DIR" -path "*/.github/workflows/*.yml" -o -path "*/.github/workflows/*.yaml" 2>/dev/null | grep -vE "$exclude_grep" || true)

  # GitLab CI
  while IFS= read -r gitlabci; do
    [[ -z "$gitlabci" ]] && continue
    echo "$gitlabci" | grep -qE "$exclude_grep" && continue
    local rel_path="${gitlabci#$SCAN_DIR/}"

    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      if echo "$line_content" | grep -qiE "(PASSWORD|SECRET|TOKEN|KEY)[[:space:]]*:[[:space:]]*[^\$\"\{\}]" 2>/dev/null; then
        if ! echo "$line_content" | grep -qE "\\\$[A-Z_]+" 2>/dev/null; then
          is_false_positive "$line_content" && continue
          local matched_part
          matched_part=$(echo "$line_content" | sed 's/^[[:space:]]*//')
          record_finding \
            "CRITICAL" \
            "vcs" \
            "GITLAB_CI_HARDCODED_SECRET" \
            "$rel_path" \
            "$lineno" \
            "$matched_part" \
            "Potential hardcoded secret in GitLab CI configuration" \
            "$matched_part" \
            "" \
            "file"
        fi
      fi
    done < <(grep -n "" "$gitlabci" 2>/dev/null || true)
  done < <(find "$SCAN_DIR" -name ".gitlab-ci.yml" -type f 2>/dev/null | grep -vE "$exclude_grep" || true)

  # Jenkinsfile
  while IFS= read -r jenkinsfile; do
    [[ -z "$jenkinsfile" ]] && continue
    echo "$jenkinsfile" | grep -qE "$exclude_grep" && continue
    local rel_path="${jenkinsfile#$SCAN_DIR/}"

    while IFS=: read -r lineno line_content; do
      [[ -z "$lineno" || -z "$line_content" ]] && continue
      if echo "$line_content" | grep -qiE "(password|secret|token|key)[[:space:]]*=[[:space:]]*['\"][^'\"]{6,}['\"]" 2>/dev/null; then
        is_false_positive "$line_content" && continue
        local matched_part
        matched_part=$(echo "$line_content" | sed 's/^[[:space:]]*//')
        record_finding \
          "CRITICAL" \
          "vcs" \
          "JENKINS_HARDCODED_SECRET" \
          "$rel_path" \
          "$lineno" \
          "$matched_part" \
          "Potential hardcoded secret in Jenkinsfile" \
          "$matched_part" \
          "" \
          "file"
      fi
    done < <(grep -n "" "$jenkinsfile" 2>/dev/null || true)
  done < <(find "$SCAN_DIR" -name "Jenkinsfile" -type f 2>/dev/null | grep -vE "$exclude_grep" || true)

  log_verbose "Pass 4 complete."
}

# =============================================================================
# PASS 5 — GIT HISTORY SCANNING
# =============================================================================

run_pass5_git_history() {
  if ! $SCAN_GIT_HISTORY || ! $IS_GIT_REPO; then
    log_info "Pass 5: Git history scan skipped."
    return
  fi

  log_info "Pass 5: Scanning git history (last $GIT_HISTORY_LIMIT commits)..."
  log_verbose "  Git root: $GIT_REPO_ROOT"

  local git_opts="--all --max-count=$GIT_HISTORY_LIMIT"

  # ── 5a: Deleted secret files ────────────────────────────────────────────
  log_verbose "  Looking for deleted secret files..."
  local deleted_secret_files
  deleted_secret_files=$(git -C "$GIT_REPO_ROOT" log $git_opts \
    --diff-filter=D --name-only --pretty=format: \
    -- "*.env" "*.pem" "*.key" "*.pfx" "*.p12" "*.jks" \
       "credentials.json" "service-account.json" "keyfile.json" \
    2>/dev/null | sort -u | grep -vE "^$" || true)

  if [[ -n "$deleted_secret_files" ]]; then
    while IFS= read -r deleted_file; do
      [[ -z "$deleted_file" ]] && continue
      record_finding \
        "HIGH" \
        "crypto" \
        "DELETED_SECRET_FILE_IN_GIT" \
        "$deleted_file" \
        "1" \
        "$deleted_file" \
        "Secret file was committed and later deleted — still in git history" \
        "git log --all -- $deleted_file" \
        "" \
        "git_history"
    done <<< "$deleted_secret_files"
  fi

  # ── 5b: AWS Access Keys ever committed ──────────────────────────────────
  log_verbose "  Searching git history for AWS access keys..."
  local search_extensions=("*.ts" "*.js" "*.py" "*.env" "*.yml" "*.yaml" "*.json")
  local search_ext_args=()
  for ext in "${search_extensions[@]}"; do
    search_ext_args+=("$ext")
  done

  local aws_hits
  aws_hits=$(git -C "$GIT_REPO_ROOT" log -p $git_opts -S "AKIA" \
    -- "${search_ext_args[@]}" 2>/dev/null \
    | grep "^+" | grep -E "AKIA[0-9A-Z]{16}" | head -20 || true)

  if [[ -n "$aws_hits" ]]; then
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      is_false_positive "$hit_line" && continue
      local matched_key
      matched_key=$(echo "$hit_line" | grep -oE "AKIA[0-9A-Z]{16}" | head -1 || echo "AKIA****")
      record_finding \
        "CRITICAL" \
        "cloud" \
        "AWS_KEY_IN_GIT_HISTORY" \
        "git-history" \
        "1" \
        "$matched_key" \
        "AWS Access Key ID found in git commit history — rotate immediately" \
        "$(echo "$hit_line" | sed 's/^+//' | sed 's/^[[:space:]]*//')" \
        "" \
        "git_history"
    done <<< "$aws_hits"
  fi

  # ── 5c: Stripe live keys ever committed ─────────────────────────────────
  log_verbose "  Searching git history for Stripe live keys..."
  local stripe_hits
  stripe_hits=$(git -C "$GIT_REPO_ROOT" log -p $git_opts -S "sk_live_" \
    -- "${search_ext_args[@]}" 2>/dev/null \
    | grep "^+" | grep -E "sk_live_[0-9a-zA-Z]{24,}" | head -20 || true)

  if [[ -n "$stripe_hits" ]]; then
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      is_false_positive "$hit_line" && continue
      local matched_key
      matched_key=$(echo "$hit_line" | grep -oE "sk_live_[0-9a-zA-Z]{24,}" | head -1 || echo "sk_live_****")
      record_finding \
        "CRITICAL" \
        "payment" \
        "STRIPE_KEY_IN_GIT_HISTORY" \
        "git-history" \
        "1" \
        "$matched_key" \
        "Stripe live secret key found in git commit history — rotate immediately" \
        "$(echo "$hit_line" | sed 's/^+//' | sed 's/^[[:space:]]*//')" \
        "" \
        "git_history"
    done <<< "$stripe_hits"
  fi

  # ── 5d: Private keys ever committed ─────────────────────────────────────
  log_verbose "  Searching git history for private key headers..."
  local pem_hits
  pem_hits=$(git -C "$GIT_REPO_ROOT" log -p $git_opts -S "-----BEGIN" \
    -- "*.ts" "*.js" "*.py" "*.pem" "*.key" "*.txt" "*.env" \
    2>/dev/null \
    | grep "^+" | grep "-----BEGIN.*PRIVATE KEY" | head -10 || true)

  if [[ -n "$pem_hits" ]]; then
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      record_finding \
        "CRITICAL" \
        "crypto" \
        "PRIVATE_KEY_IN_GIT_HISTORY" \
        "git-history" \
        "1" \
        "-----BEGIN PRIVATE KEY-----" \
        "Private key PEM block found in git commit history — revoke certificate immediately" \
        "$(echo "$hit_line" | sed 's/^+//' | sed 's/^[[:space:]]*//')" \
        "" \
        "git_history"
    done <<< "$pem_hits"
  fi

  # ── 5e: OpenAI keys ever committed ──────────────────────────────────────
  log_verbose "  Searching git history for OpenAI keys..."
  local openai_hits
  openai_hits=$(git -C "$GIT_REPO_ROOT" log -p $git_opts -S "sk-" \
    -- "${search_ext_args[@]}" 2>/dev/null \
    | grep "^+" | grep -E "sk-(proj-|ant-api|[0-9a-zA-Z]{48})" | head -10 || true)

  if [[ -n "$openai_hits" ]]; then
    while IFS= read -r hit_line; do
      [[ -z "$hit_line" ]] && continue
      is_false_positive "$hit_line" && continue
      local matched_key
      matched_key=$(echo "$hit_line" | grep -oE "sk-[0-9a-zA-Z\-_]{20,}" | head -1 | head -c 30 || echo "sk-****")
      record_finding \
        "CRITICAL" \
        "ai" \
        "AI_KEY_IN_GIT_HISTORY" \
        "git-history" \
        "1" \
        "$matched_key..." \
        "AI API key (OpenAI/Anthropic) found in git commit history — rotate immediately" \
        "$(echo "$hit_line" | sed 's/^+//' | sed 's/^[[:space:]]*//')" \
        "" \
        "git_history"
    done <<< "$openai_hits"
  fi

  log_verbose "Pass 5 complete."
}

# =============================================================================
# DEDUPLICATION
# =============================================================================

deduplicate_findings() {
  if [[ ! -f "$WORK_DIR/findings.tsv" ]]; then
    return
  fi

  # Sort and deduplicate on file+line+name (columns 3,4,5)
  sort -u -t$'\t' -k3,3 -k4,4 -k5,5 "$WORK_DIR/findings.tsv" > "$WORK_DIR/findings_dedup.tsv"
  mv "$WORK_DIR/findings_dedup.tsv" "$WORK_DIR/findings.tsv"
}

# =============================================================================
# COUNT FINDINGS
# =============================================================================

tally_findings() {
  if [[ ! -f "$WORK_DIR/findings.tsv" ]]; then
    COUNT_CRITICAL=0
    COUNT_HIGH=0
    COUNT_MEDIUM=0
    COUNT_LOW=0
    return
  fi

  # Use awk to count lines beginning with each severity (avoids bash 3.2 $'\t' issues)
  COUNT_CRITICAL=$(awk -F'\t' '$1=="CRITICAL"{c++} END{print c+0}' "$WORK_DIR/findings.tsv" 2>/dev/null | tr -d '[:space:]')
  COUNT_HIGH=$(    awk -F'\t' '$1=="HIGH"{c++} END{print c+0}'     "$WORK_DIR/findings.tsv" 2>/dev/null | tr -d '[:space:]')
  COUNT_MEDIUM=$(  awk -F'\t' '$1=="MEDIUM"{c++} END{print c+0}'   "$WORK_DIR/findings.tsv" 2>/dev/null | tr -d '[:space:]')
  COUNT_LOW=$(     awk -F'\t' '$1=="LOW"{c++} END{print c+0}'      "$WORK_DIR/findings.tsv" 2>/dev/null | tr -d '[:space:]')
  COUNT_CRITICAL=${COUNT_CRITICAL:-0}
  COUNT_HIGH=${COUNT_HIGH:-0}
  COUNT_MEDIUM=${COUNT_MEDIUM:-0}
  COUNT_LOW=${COUNT_LOW:-0}
}

# =============================================================================
# PYTHON HELPER SETUP
# Writing Python scripts to WORK_DIR avoids heredoc + parenthesis parse issues
# in bash -n / runtime. All Python is in plain .py files executed by python3.
# =============================================================================

setup_python_helpers() {
  $PYTHON3_AVAILABLE || return 0

  # ── py_findings.py : convert findings.tsv to JSON array with redaction ──
  cat > "$WORK_DIR/py_findings.py" << 'ENDOFPYTHON'
import sys, json

def redact(s):
    if not s or len(s) <= 12:
        return '*' * len(s) if s else ''
    return s[:8] + '****' + s[-4:]

tsv_file = sys.argv[1]
findings = []

try:
    with open(tsv_file, 'r', encoding='utf-8', errors='replace') as fh:
        for raw in fh:
            parts = raw.rstrip('\n').split('\t')
            if len(parts) < 10:
                parts += [''] * (10 - len(parts))
            severity, category, name, filepath, lineno, match, description, context, entropy, source = parts[:10]
            findings.append({
                "severity": severity,
                "category": category,
                "name": name,
                "file": filepath,
                "line": int(lineno) if lineno.isdigit() else 1,
                "match": redact(match),
                "description": description,
                "context_line": context[:200] if context else None,
                "entropy": float(entropy) if entropy and entropy not in ('', '0.00', '0') else None,
                "source": source or "file"
            })
except FileNotFoundError:
    pass

print(json.dumps(findings, indent=2))
ENDOFPYTHON

  # ── py_json_wrap.py : wrap findings array in top-level scan object ──────
  cat > "$WORK_DIR/py_json_wrap.py" << 'ENDOFPYTHON'
import sys, json

timestamp, directory, git_scanned, crit, high, med, low, total, sev_filter, cat_filter = sys.argv[1:11]
findings_raw = sys.stdin.read().strip()
findings = json.loads(findings_raw) if findings_raw else []

data = {
    "scan_timestamp": timestamp,
    "directory": directory,
    "git_history_scanned": git_scanned == "true",
    "summary": {
        "critical": int(crit),
        "high": int(high),
        "medium": int(med),
        "low": int(low),
        "total": int(total)
    },
    "filters": {
        "severity": sev_filter,
        "category": cat_filter
    },
    "findings": findings
}

print(json.dumps(data, indent=2))
ENDOFPYTHON

  # ── py_sarif.py : emit SARIF 2.1.0 from findings.tsv ───────────────────
  cat > "$WORK_DIR/py_sarif.py" << 'ENDOFPYTHON'
import sys, json

tsv_file = sys.argv[1] if len(sys.argv) > 1 else None
scan_dir = sys.argv[2] if len(sys.argv) > 2 else "."

SEV_LEVEL = {"CRITICAL": "error", "HIGH": "error", "MEDIUM": "warning", "LOW": "note"}
SEV_SCORE = {"CRITICAL": 9.8, "HIGH": 7.5, "MEDIUM": 5.0, "LOW": 2.5}

rules = {}
results = []

if tsv_file:
    try:
        with open(tsv_file, 'r', encoding='utf-8', errors='replace') as fh:
            for raw in fh:
                parts = raw.rstrip('\n').split('\t')
                if len(parts) < 10:
                    parts += [''] * (10 - len(parts))
                severity, category, name, filepath, lineno, match, description, context, entropy, source = parts[:10]

                rule_id = "CRED/" + name
                if rule_id not in rules:
                    rules[rule_id] = {
                        "id": rule_id,
                        "name": name,
                        "shortDescription": {"text": description},
                        "fullDescription": {"text": description + " (category: " + category + ")"},
                        "defaultConfiguration": {"level": SEV_LEVEL.get(severity, "warning")},
                        "properties": {
                            "security-severity": str(SEV_SCORE.get(severity, 5.0)),
                            "category": category,
                            "tags": ["security", "credentials", category]
                        }
                    }

                line_num = int(lineno) if lineno.isdigit() else 1
                results.append({
                    "ruleId": rule_id,
                    "level": SEV_LEVEL.get(severity, "warning"),
                    "message": {"text": description + " - match redacted for safety"},
                    "locations": [{
                        "physicalLocation": {
                            "artifactLocation": {
                                "uri": filepath,
                                "uriBaseId": "%SRCROOT%"
                            },
                            "region": {"startLine": line_num, "startColumn": 1}
                        }
                    }],
                    "properties": {
                        "severity": severity,
                        "category": category,
                        "source": source,
                        "entropy": float(entropy) if entropy and entropy not in ('', '0.00', '0') else None
                    }
                })
    except FileNotFoundError:
        pass

sarif = {
    "version": "2.1.0",
    "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
    "runs": [{
        "tool": {
            "driver": {
                "name": "credential-scanner",
                "version": "1.0.0",
                "informationUri": "https://github.com/styai/security-scanner",
                "rules": list(rules.values())
            }
        },
        "results": results,
        "invocations": [{
            "executionSuccessful": True,
            "commandLine": "credential-scanner.sh",
            "workingDirectory": {"uri": scan_dir}
        }]
    }]
}

print(json.dumps(sarif, indent=2))
ENDOFPYTHON

  log_verbose "Python helper scripts written to $WORK_DIR"
}

# =============================================================================
# OUTPUT FORMATTERS
# =============================================================================

severity_color() {
  local sev
  sev="$(to_upper "$1")"
  case "$sev" in
    CRITICAL) echo -n "$RED" ;;
    HIGH)     echo -n "$ORANGE" ;;
    MEDIUM)   echo -n "$YELLOW" ;;
    LOW)      echo -n "$GREEN" ;;
    *)        echo -n "$RESET" ;;
  esac
}

output_text() {
  local out_target="${1:-/dev/stdout}"

  {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  CREDENTIAL SCAN RESULTS"
    echo "  Directory: $SCAN_DIR"
    echo "  Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    if [[ ! -f "$WORK_DIR/findings.tsv" || ! -s "$WORK_DIR/findings.tsv" ]]; then
      echo "  No findings. Repository appears clean."
      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      echo "  Summary: 0 CRITICAL, 0 HIGH, 0 MEDIUM, 0 LOW"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      return
    fi

    # Sort by severity order: CRITICAL first, then HIGH, MEDIUM, LOW
    # Write sorted findings to a temp file, then iterate using cut (field extraction)
    # to avoid bash read+IFS tab parsing issues with empty fields.
    local sorted_tsv="$WORK_DIR/sorted_findings.tsv"
    {
      awk -F'\t' '$1=="CRITICAL"' "$WORK_DIR/findings.tsv" 2>/dev/null || true
      awk -F'\t' '$1=="HIGH"'     "$WORK_DIR/findings.tsv" 2>/dev/null || true
      awk -F'\t' '$1=="MEDIUM"'   "$WORK_DIR/findings.tsv" 2>/dev/null || true
      awk -F'\t' '$1=="LOW"'      "$WORK_DIR/findings.tsv" 2>/dev/null || true
    } > "$sorted_tsv"

    local total_findings
    total_findings=$(wc -l < "$sorted_tsv" | tr -d '[:space:]')
    local idx=0
    while [[ "$idx" -lt "$total_findings" ]]; do
      idx=$((idx + 1))
      local tsv_line
      tsv_line=$(sed -n "${idx}p" "$sorted_tsv")

      local severity category name filepath lineno description context entropy source
      severity=$(   echo "$tsv_line" | cut -f1)
      category=$(   echo "$tsv_line" | cut -f2)
      name=$(       echo "$tsv_line" | cut -f3)
      filepath=$(   echo "$tsv_line" | cut -f4)
      lineno=$(     echo "$tsv_line" | cut -f5)
      # skip field 6 (match — redacted in JSON output only)
      description=$(echo "$tsv_line" | cut -f7)
      context=$(    echo "$tsv_line" | cut -f8)
      entropy=$(    echo "$tsv_line" | cut -f9)
      source=$(     echo "$tsv_line" | cut -f10)

      local sev_color
      sev_color=$(severity_color "$severity")

      echo -e "${sev_color}${BOLD}[$severity]${RESET} $description"
      echo    "  Name:     $name"
      echo    "  File:     $filepath:$lineno"
      echo    "  Category: $category"
      if [[ "$source" == "git_history" ]]; then
        echo  "  Source:   git commit history"
      fi
      if [[ -n "$entropy" && "$entropy" != "0.00" && "$entropy" != "0" ]]; then
        local elabel
        elabel=$(entropy_label "$entropy")
        echo  "  Entropy:  $entropy ($elabel)"
      fi
      if [[ -n "$context" ]]; then
        local ctx_display
        ctx_display=$(echo "$context" | cut -c1-120)
        [[ "${#context}" -gt 120 ]] && ctx_display="${ctx_display}..."
        echo  "  Context:  $ctx_display"
      fi
      echo ""
    done

    echo "───────────────────────────────────────────────────────────────"
    echo -e "  Summary: ${RED}${COUNT_CRITICAL} CRITICAL${RESET}, ${ORANGE}${COUNT_HIGH} HIGH${RESET}, ${YELLOW}${COUNT_MEDIUM} MEDIUM${RESET}, ${GREEN}${COUNT_LOW} LOW${RESET}"
    local total=$((COUNT_CRITICAL + COUNT_HIGH + COUNT_MEDIUM + COUNT_LOW))
    echo    "  Total:   $total finding(s)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

  } | if [[ "$out_target" == "/dev/stdout" ]]; then cat; else tee "$out_target" > /dev/null; cat "$out_target"; fi
}

output_json() {
  local out_target="${1:-/dev/stdout}"
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Build findings JSON array using python3 for proper escaping
  local findings_json="[]"
  if [[ -f "$WORK_DIR/findings.tsv" && -s "$WORK_DIR/findings.tsv" ]]; then
    findings_json=$(python3 "$WORK_DIR/py_findings.py" "$WORK_DIR/findings.tsv" 2>/dev/null || echo "[]")
  fi

  local git_scanned
  $SCAN_GIT_HISTORY && git_scanned="true" || git_scanned="false"
  local total=$((COUNT_CRITICAL + COUNT_HIGH + COUNT_MEDIUM + COUNT_LOW))

  local json_output
  json_output=$(echo "$findings_json" | python3 "$WORK_DIR/py_json_wrap.py" \
      "$timestamp" \
      "$SCAN_DIR" \
      "$git_scanned" \
      "$COUNT_CRITICAL" \
      "$COUNT_HIGH" \
      "$COUNT_MEDIUM" \
      "$COUNT_LOW" \
      "$total" \
      "$FILTER_SEVERITY" \
      "$FILTER_CATEGORY" \
      2>/dev/null || echo "{}")

  if [[ "$out_target" == "/dev/stdout" ]]; then
    echo "$json_output"
  else
    echo "$json_output" > "$out_target"
    echo "$json_output"
  fi
}

output_sarif() {
  local out_target="${1:-/dev/stdout}"

  # SARIF 2.1.0 format — use pre-written Python helper to avoid heredoc/bash issues
  local sarif_output
  sarif_output=$(python3 "$WORK_DIR/py_sarif.py" "$WORK_DIR/findings.tsv" "$SCAN_DIR" 2>/dev/null)
  # If python3 failed or returned empty, emit minimal valid SARIF
  if [[ -z "$sarif_output" ]]; then
    sarif_output='{"version":"2.1.0","runs":[]}'
  fi

  if [[ "$out_target" == "/dev/stdout" ]]; then
    echo "$sarif_output"
  else
    echo "$sarif_output" > "$out_target"
    echo "$sarif_output"
  fi
}

# =============================================================================
# MAIN BANNER
# =============================================================================

print_banner() {
  echo "" >&2
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════════╗${RESET}" >&2
  echo -e "${BOLD}${CYAN}  ║  Credential Scanner                          ║${RESET}" >&2
  echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════════╝${RESET}" >&2
  echo "" >&2
  echo -e "  ${BOLD}Directory:${RESET}  $SCAN_DIR" >&2
  echo -e "  ${BOLD}Format:${RESET}     $OUTPUT_FORMAT" >&2
  echo -e "  ${BOLD}Severity:${RESET}   $FILTER_SEVERITY" >&2
  echo -e "  ${BOLD}Category:${RESET}   $FILTER_CATEGORY" >&2
  echo -e "  ${BOLD}Git history:${RESET} $(${SCAN_GIT_HISTORY} && echo "enabled (last $GIT_HISTORY_LIMIT commits)" || echo "disabled")" >&2
  echo "" >&2
}

# =============================================================================
# PROGRESS HELPERS
# =============================================================================

print_section() {
  echo -e "\n${BOLD}${CYAN}  ──────────────────────────────────────────────${RESET}" >&2
  echo -e "  ${BOLD}$1${RESET}" >&2
  echo -e "${BOLD}${CYAN}  ──────────────────────────────────────────────${RESET}" >&2
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  parse_args "$@"

  # Set up work directory
  WORK_DIR="$(mktemp -d /tmp/credential-scanner.XXXXXX)"
  touch "$WORK_DIR/findings.tsv"

  check_dependencies
  setup_python_helpers

  print_banner

  # ── Run all passes ────────────────────────────────────────────────────────

  print_section "Pass 1: Direct Pattern Matching"
  run_pass1

  print_section "Pass 2: Contextual Pattern Matching"
  run_pass2

  print_section "Pass 3: Entropy Analysis"
  run_pass3

  print_section "Pass 4: File-Based Checks"
  run_pass4

  print_section "Pass 5: Git History Scanning"
  run_pass5_git_history

  # ── Post-process ───────────────────────────────────────────────────────────

  log_info "Deduplicating findings..."
  deduplicate_findings

  tally_findings

  local total=$((COUNT_CRITICAL + COUNT_HIGH + COUNT_MEDIUM + COUNT_LOW))
  log_info "Scan complete — $total finding(s) found."
  echo "" >&2

  # ── Output ────────────────────────────────────────────────────────────────

  local out_target="/dev/stdout"
  if [[ -n "$OUTPUT_FILE" ]]; then
    # Create parent directory if needed
    local out_dir
    out_dir="$(dirname "$OUTPUT_FILE")"
    [[ "$out_dir" != "." ]] && mkdir -p "$out_dir"
    out_target="$OUTPUT_FILE"
  fi

  case "$OUTPUT_FORMAT" in
    text)  output_text  "$out_target" ;;
    json)  output_json  "$out_target" ;;
    sarif) output_sarif "$out_target" ;;
  esac

  if [[ -n "$OUTPUT_FILE" ]]; then
    echo -e "  ${GREEN}Results written to: $OUTPUT_FILE${RESET}" >&2
  fi

  # ── Exit code ─────────────────────────────────────────────────────────────
  # Ensure all counters are clean integers (strip any whitespace/newlines)
  COUNT_CRITICAL=$(echo "$COUNT_CRITICAL" | tr -d '[:space:]')
  COUNT_HIGH=$(echo "$COUNT_HIGH" | tr -d '[:space:]')
  COUNT_MEDIUM=$(echo "$COUNT_MEDIUM" | tr -d '[:space:]')
  COUNT_LOW=$(echo "$COUNT_LOW" | tr -d '[:space:]')
  COUNT_CRITICAL=${COUNT_CRITICAL:-0}
  COUNT_HIGH=${COUNT_HIGH:-0}
  COUNT_MEDIUM=${COUNT_MEDIUM:-0}
  COUNT_LOW=${COUNT_LOW:-0}

  if [[ "$COUNT_CRITICAL" -gt 0 ]]; then
    exit 3
  elif [[ "$COUNT_HIGH" -gt 0 ]]; then
    exit 2
  elif [[ "$((COUNT_MEDIUM + COUNT_LOW))" -gt 0 ]]; then
    exit 1
  else
    exit 0
  fi
}

main "$@"

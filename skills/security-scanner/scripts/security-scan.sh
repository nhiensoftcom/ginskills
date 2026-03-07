#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Security Scanner — Automated Checks
# Aligned with OWASP Top 10:2025 & OWASP LLM Top 10:2025
#
# Scans the monorepo for common security issues:
#   - Hardcoded secrets & API keys (A04)
#   - Missing auth guards (A01)
#   - Unsafe patterns: eval, dangerouslySetInnerHTML (A05)
#   - Console logging of sensitive data (A09)
#   - Dependency vulnerabilities & supply chain (A03)
#   - LLM/AI agent risks (LLM01, LLM06)
#   - Exceptional condition handling (A10)
#   - Lockfile integrity & lifecycle scripts
#
# Auto-detects backend, frontend, and mobile directories.
#
# Usage:
#   ./security-scan.sh all            # scan everything
#   ./security-scan.sh backend        # backend only
#   ./security-scan.sh frontend       # frontend only
#   ./security-scan.sh mobile         # mobile only
#   ./security-scan.sh supply-chain   # supply chain only
#   ./security-scan.sh llm            # LLM/AI security only
#   ./security-scan.sh secrets        # comprehensive credential scan (100+ patterns)
#
# Environment variables (override auto-detection):
#   BE_DIR=./my-backend  FE_DIR=./my-frontend  MOBILE_DIR=./my-mobile  ./security-scan.sh all
#
# Output: JSON report at ./security-output/scan-report.json
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../../.." && pwd)"

# Source the comprehensive patterns database
if [ -f "$SCRIPT_DIR/secret-patterns.sh" ]; then
  source "$SCRIPT_DIR/secret-patterns.sh"
  PATTERNS_LOADED=true
else
  PATTERNS_LOADED=false
fi

# ─── Auto-detect project directories ─────────────────────────
detect_dir() {
  local kind="$1"
  shift
  for candidate in "$@"; do
    if [ -d "$REPO_ROOT/$candidate" ] && [ -f "$REPO_ROOT/$candidate/package.json" ]; then
      echo "$REPO_ROOT/$candidate"
      return
    fi
  done
  echo ""
}

detect_src() {
  local dir="$1"
  if [ -n "$dir" ] && [ -d "$dir/src" ]; then
    echo "$dir/src"
  else
    echo ""
  fi
}

BE_DIR="${BE_DIR:-$(detect_dir backend backend be-* server api apps/api apps/backend)}"
FE_DIR="${FE_DIR:-$(detect_dir frontend frontend web-* client apps/web apps/frontend)}"
MOBILE_DIR="${MOBILE_DIR:-$(detect_dir mobile mobile *-mobile apps/mobile)}"

BE_SRC="$(detect_src "$BE_DIR")"
FE_SRC="$(detect_src "$FE_DIR")"
MOBILE_SRC="$(detect_src "$MOBILE_DIR")"

BE_NAME="$([ -n "$BE_DIR" ] && basename "$BE_DIR" || echo "backend")"
FE_NAME="$([ -n "$FE_DIR" ] && basename "$FE_DIR" || echo "frontend")"
MOBILE_NAME="$([ -n "$MOBILE_DIR" ] && basename "$MOBILE_DIR" || echo "mobile")"

OUTPUT_DIR="$SCRIPT_DIR/../security-output"
REPORT="$OUTPUT_DIR/scan-report.json"

TARGET="${1:-all}"

mkdir -p "$OUTPUT_DIR"

# ─── Counters ────────────────────────────────────────────────
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0
FINDINGS=()

log()  { echo "  [scan] $*"; }
finding() {
  local sev="$1" category="$2" file="$3" detail="$4"
  echo "  [$sev] $category: $detail"
  echo "         → $file"
  FINDINGS+=("{\"severity\":\"$sev\",\"category\":\"$category\",\"file\":\"$file\",\"detail\":$(python3 -c "import json; print(json.dumps('$detail'))" 2>/dev/null || echo "\"$detail\"")}")
  case $sev in
    CRITICAL) CRITICAL=$((CRITICAL + 1)) ;;
    HIGH)     HIGH=$((HIGH + 1)) ;;
    MEDIUM)   MEDIUM=$((MEDIUM + 1)) ;;
    LOW)      LOW=$((LOW + 1)) ;;
  esac
}

# ─── Scan Functions ──────────────────────────────────────────

scan_hardcoded_secrets() {
  local dir="$1" label="$2"
  log "Scanning $label for hardcoded secrets..."

  if [ "$PATTERNS_LOADED" = true ]; then
    # ─── Pass 1: Direct pattern matching (SECRET_PATTERNS) ───
    _scan_with_patterns "$dir" "$label" "SECRET_PATTERNS"

    # ─── Pass 2: Contextual pattern matching (CONTEXTUAL_PATTERNS) ───
    _scan_with_patterns "$dir" "$label" "CONTEXTUAL_PATTERNS"

    # ─── Pass 3: Sensitive files check ───
    _scan_sensitive_files "$dir" "$label"
  else
    # Fallback: basic patterns if patterns database not available
    _scan_basic_secrets "$dir" "$label"
  fi
}

_is_false_positive() {
  local line="$1"
  for fp in "${FALSE_POSITIVE_PATTERNS[@]}"; do
    if echo "$line" | grep -qiF -- "$fp" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

_build_include_flags() {
  local flags=""
  for ext in ts tsx js jsx mjs cjs json yaml yml env sh; do
    flags="$flags --include=*.$ext"
  done
  echo "$flags"
}

_scan_with_patterns() {
  local dir="$1" label="$2" array_name="$3"
  local -n patterns_ref="$array_name"
  local include_flags
  include_flags="$(_build_include_flags)"

  for pattern_entry in "${patterns_ref[@]}"; do
    IFS='|' read -r sev cat name regex desc <<< "$pattern_entry"
    [ -z "$regex" ] && continue

    while IFS=: read -r file line content; do
      [ -z "$file" ] && continue
      # Skip excluded paths
      local skip=false
      for excl in "${EXCLUDE_PATHS[@]}"; do
        if echo "$file" | grep -qE "$excl" 2>/dev/null; then
          skip=true
          break
        fi
      done
      [ "$skip" = true ] && continue

      # Skip false positives
      if _is_false_positive "$content"; then
        continue
      fi

      finding "$sev" "$name" "${file#$REPO_ROOT/}:$line" "$desc"
    done < <(grep -rn -E -- "$regex" \
      --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
      --include="*.mjs" --include="*.cjs" --include="*.json" --include="*.yaml" \
      --include="*.yml" --include="*.env" --include="*.sh" --include="*.py" \
      "$dir" 2>/dev/null | grep -v "node_modules" | head -30 || true)
  done
}

_scan_sensitive_files() {
  local dir="$1" label="$2"
  log "Checking $label for sensitive files..."

  # Private key files
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "SENSITIVE_FILE" "${file#$REPO_ROOT/}" "Private key file found in source tree"
  done < <(find "$dir" \( -name "*.pem" -o -name "*.key" -o -name "*.p12" -o -name "*.pfx" -o -name "*.jks" \) 2>/dev/null | grep -v "node_modules" | head -10 || true)

  # Credential files
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "CREDENTIAL_FILE" "${file#$REPO_ROOT/}" "Credential file found in source tree"
  done < <(find "$dir" \( -name "credentials.json" -o -name "service-account*.json" -o -name "keyfile.json" -o -name ".npmrc" \) 2>/dev/null | grep -v "node_modules" | head -10 || true)

  # .env files that shouldn't be committed
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    local basename
    basename=$(basename "$file")
    # Skip .env.example, .env.sample, .env.template
    case "$basename" in
      .env.example|.env.sample|.env.template) continue ;;
    esac
    finding "CRITICAL" "ENV_FILE_COMMITTED" "${file#$REPO_ROOT/}" ".env file found in source (should be in .gitignore)"
  done < <(find "$dir" -maxdepth 3 -name ".env" -o -name ".env.local" -o -name ".env.production" -o -name ".env.staging" 2>/dev/null | grep -v "node_modules" | head -10 || true)
}

_scan_basic_secrets() {
  local dir="$1" label="$2"
  # Fallback basic scan when patterns database not loaded
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "HARDCODED_SECRET" "${file#$REPO_ROOT/}:$line" "Possible hardcoded secret"
  done < <(grep -rn \
    -e "api[_-]\?key\s*[:=]\s*['\"][a-zA-Z0-9_-]\{16,\}" \
    -e "password\s*[:=]\s*['\"][^'\"]\{6,\}" \
    -e "secret\s*[:=]\s*['\"][a-zA-Z0-9_-]\{16,\}" \
    -e "Bearer\s\+[a-zA-Z0-9_-]\{20,\}" \
    --include="*.ts" --include="*.tsx" --include="*.mjs" --include="*.js" \
    "$dir" 2>/dev/null | grep -v "node_modules" | grep -v ".env" | grep -v "example" | grep -v "YOUR_" | grep -v "xxx" | head -20 || true)

  # Private keys
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "PRIVATE_KEY" "${file#$REPO_ROOT/}:$line" "Private key found in source"
  done < <(grep -rn "PRIVATE KEY" --include="*.ts" --include="*.tsx" --include="*.mjs" "$dir" 2>/dev/null | grep -v "node_modules" | head -5 || true)
}

scan_auth_guards() {
  local dir="$1"
  log "Scanning for missing auth guards..."

  # Controllers without UseGuards
  while IFS= read -r file; do
    if ! grep -q "UseGuards\|Public\|@Public" "$file" 2>/dev/null; then
      finding "HIGH" "MISSING_AUTH_GUARD" "${file#$REPO_ROOT/}" "Controller has no auth guard"
    fi
  done < <(find "$dir" -name "*.controller.ts" 2>/dev/null | grep -v "node_modules" | grep -v "app.controller" | grep -v "health")
}

scan_injection_risks() {
  local dir="$1" label="$2"
  log "Scanning $label for injection risks..."

  # eval / Function constructor
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "CODE_INJECTION" "${file#$REPO_ROOT/}:$line" "Unsafe eval() or Function() usage"
  done < <(grep -rn "\beval\s*(\|new\s\+Function\s*(" --include="*.ts" --include="*.tsx" --include="*.mjs" "$dir" 2>/dev/null | grep -v "node_modules" | grep -v "eslint" | head -10 || true)

  # dangerouslySetInnerHTML
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "HIGH" "XSS_RISK" "${file#$REPO_ROOT/}:$line" "dangerouslySetInnerHTML with potential user content"
  done < <(grep -rn "dangerouslySetInnerHTML" --include="*.tsx" --include="*.ts" "$dir" 2>/dev/null | grep -v "node_modules" | head -10 || true)

  # $where in MongoDB queries
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "CRITICAL" "NOSQL_INJECTION" "${file#$REPO_ROOT/}:$line" "MongoDB \$where usage — potential NoSQL injection"
  done < <(grep -rn '"\$where"\|{.*\$where' --include="*.ts" "$dir" 2>/dev/null | grep -v "node_modules" | head -10 || true)
}

scan_sensitive_logging() {
  local dir="$1" label="$2"
  log "Scanning $label for sensitive data in logs..."

  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "MEDIUM" "SENSITIVE_LOG" "${file#$REPO_ROOT/}:$line" "Possible sensitive data in console output"
  done < <(grep -rn \
    -e "console\.\(log\|info\|debug\).*\(token\|password\|secret\|key\|auth\|credential\)" \
    --include="*.ts" --include="*.tsx" --include="*.mjs" \
    "$dir" 2>/dev/null | grep -v "node_modules" | grep -vi "TODO\|FIXME\|example" | head -15 || true)
}

scan_unsafe_cors() {
  local dir="$1"
  log "Scanning for unsafe CORS configuration..."

  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "HIGH" "CORS_WILDCARD" "${file#$REPO_ROOT/}:$line" "CORS wildcard (*) configuration found"
  done < <(grep -rn "origin.*\*\|allowedOrigins.*\*\|'*'" --include="*.ts" "$dir" 2>/dev/null | grep -vi "comment\|jsdoc" | grep -v "node_modules" | head -5 || true)
}

scan_unsafe_csp() {
  local dir="$1"
  log "Scanning for unsafe CSP directives..."

  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "HIGH" "CSP_UNSAFE_INLINE" "${file#$REPO_ROOT/}:$line" "CSP uses unsafe-inline — XSS protection weakened"
  done < <(grep -rn "unsafe-inline\|unsafe-eval" --include="*.ts" "$dir" 2>/dev/null | grep -v "node_modules" | head -5 || true)
}

scan_env_exposure() {
  local dir="$1" label="$2"
  log "Scanning $label for env variable exposure..."

  # NEXT_PUBLIC_ with sensitive-looking names
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "HIGH" "ENV_EXPOSURE" "${file#$REPO_ROOT/}:$line" "Potentially sensitive env var exposed to client"
  done < <(grep -rn "NEXT_PUBLIC_.*\(SECRET\|KEY\|PASSWORD\|TOKEN\)" --include="*.ts" --include="*.tsx" "$dir" 2>/dev/null | grep -v "node_modules" | head -5 || true)
}

scan_deps() {
  local dir="$1" label="$2"
  if [ -f "$dir/package.json" ] && [ -d "$dir/node_modules" ]; then
    log "Auditing $label dependencies..."
    local audit_output
    audit_output=$(cd "$dir" && npm audit --json 2>/dev/null || true)
    local critical_count high_count
    critical_count=$(echo "$audit_output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('vulnerabilities',{}).get('critical',0))" 2>/dev/null || echo "0")
    high_count=$(echo "$audit_output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('metadata',{}).get('vulnerabilities',{}).get('high',0))" 2>/dev/null || echo "0")
    if [ "$critical_count" -gt 0 ]; then
      finding "CRITICAL" "DEP_VULNERABILITY" "$label/package.json" "$critical_count critical dependency vulnerabilities"
    fi
    if [ "$high_count" -gt 0 ]; then
      finding "HIGH" "DEP_VULNERABILITY" "$label/package.json" "$high_count high dependency vulnerabilities"
    fi
  else
    log "  [skip] $label — node_modules not found"
  fi
}

scan_supply_chain() {
  local dir="$1" label="$2"
  log "Scanning $label supply chain..."

  # Check lockfile exists and is committed
  if [ -f "$dir/package-lock.json" ] || [ -f "$dir/pnpm-lock.yaml" ] || [ -f "$dir/yarn.lock" ]; then
    log "  Lockfile found ✓"
  else
    finding "HIGH" "NO_LOCKFILE" "$label/" "No lockfile found — dependency resolution not deterministic"
  fi

  # Dangerous lifecycle scripts in dependencies
  if [ -f "$dir/package.json" ]; then
    while IFS= read -r dep_dir; do
      local pkg_json="$dep_dir/package.json"
      [ ! -f "$pkg_json" ] && continue
      if grep -q '"preinstall"\|"postinstall"' "$pkg_json" 2>/dev/null; then
        local pkg_name
        pkg_name=$(python3 -c "import json; print(json.load(open('$pkg_json')).get('name','unknown'))" 2>/dev/null || echo "unknown")
        # Skip well-known packages
        case "$pkg_name" in
          esbuild|sharp|@swc/*|turbo|node-gyp|core-js|husky|cypress) continue ;;
        esac
        finding "MEDIUM" "LIFECYCLE_SCRIPT" "$label/node_modules/$pkg_name" "Package has preinstall/postinstall lifecycle scripts"
      fi
    done < <(find "$dir/node_modules" -maxdepth 2 -name "package.json" -exec dirname {} \; 2>/dev/null | head -50)
  fi

  # Check for @nestjs/devtools-integration CVE-2025-54782
  if [ -f "$dir/node_modules/@nestjs/devtools-integration/package.json" ]; then
    local devtools_ver
    devtools_ver=$(python3 -c "import json; print(json.load(open('$dir/node_modules/@nestjs/devtools-integration/package.json')).get('version','0.0.0'))" 2>/dev/null || echo "0.0.0")
    if python3 -c "from packaging.version import Version; exit(0 if Version('$devtools_ver') <= Version('0.2.0') else 1)" 2>/dev/null; then
      finding "CRITICAL" "CVE_2025_54782" "$label/@nestjs/devtools-integration" "CVE-2025-54782: RCE vulnerability in devtools-integration ≤0.2.0 (current: $devtools_ver)"
    fi
  fi

  # npm audit signatures (if npm 9+)
  if [ -d "$dir/node_modules" ]; then
    local sig_output
    sig_output=$(cd "$dir" && npm audit signatures 2>&1 || true)
    if echo "$sig_output" | grep -qi "invalid\|tampered"; then
      finding "CRITICAL" "SIGNATURE_INVALID" "$label/package.json" "npm audit signatures found tampered packages"
    fi
  fi
}

scan_llm_security() {
  local dir="$1"
  log "Scanning for LLM/AI agent security risks..."

  # Prompt injection vectors — unsanitized user input in prompts
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "HIGH" "PROMPT_INJECTION_RISK" "${file#$REPO_ROOT/}:$line" "User input may be concatenated directly into LLM prompt"
  done < <(grep -rn \
    -e 'prompt.*\${.*\(input\|query\|message\|content\|user\)' \
    -e 'prompt.*\+.*\(input\|query\|message\|content\|user\)' \
    -e 'template.*\${.*\(input\|query\|message\|content\)' \
    --include="*.ts" --include="*.mjs" \
    "$dir" 2>/dev/null | grep -v "node_modules" | grep -v "test" | grep -v "spec" | head -15 || true)

  # System prompt exposure
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "MEDIUM" "SYSTEM_PROMPT_EXPOSURE" "${file#$REPO_ROOT/}:$line" "System prompt may be logged or returned in response"
  done < <(grep -rn \
    -e 'console\.log.*system.*prompt\|console\.log.*systemMessage' \
    -e 'response.*system.*prompt\|return.*system.*prompt' \
    --include="*.ts" \
    "$dir" 2>/dev/null | grep -v "node_modules" | head -5 || true)

  # Excessive agency — tools without permission checks
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "MEDIUM" "EXCESSIVE_AGENCY" "${file#$REPO_ROOT/}:$line" "LangGraph tool definition — verify permission scoping"
  done < <(grep -rn \
    -e '@tool\|new DynamicTool\|StructuredTool\|createTool' \
    --include="*.ts" \
    "$dir" 2>/dev/null | grep -v "node_modules" | head -10 || true)

  # Unbounded LLM consumption — missing token limits
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    if ! grep -q "maxTokens\|max_tokens\|maxOutputTokens" "$file" 2>/dev/null; then
      finding "MEDIUM" "UNBOUNDED_LLM" "${file#$REPO_ROOT/}:$line" "LLM call without explicit token limit"
    fi
  done < <(grep -rln \
    -e 'invoke\|generate\|chat\|complete' \
    --include="*.ts" \
    "$dir/features/ai-agents" "$dir/features/llm" 2>/dev/null | head -10 || true)

  # Unsanitized AI output rendering — scan frontend and mobile if available
  local ai_render_dirs=()
  [ -n "$FE_SRC" ] && [ -d "$FE_SRC" ] && ai_render_dirs+=("$FE_SRC")
  [ -n "$MOBILE_SRC" ] && [ -d "$MOBILE_SRC" ] && ai_render_dirs+=("$MOBILE_SRC")
  if [ ${#ai_render_dirs[@]} -gt 0 ]; then
    while IFS=: read -r file line content; do
      [ -z "$file" ] && continue
      finding "HIGH" "UNSANITIZED_AI_OUTPUT" "${file#$REPO_ROOT/}:$line" "AI-generated content rendered with dangerouslySetInnerHTML"
    done < <(grep -rn "dangerouslySetInnerHTML" --include="*.tsx" "${ai_render_dirs[@]}" 2>/dev/null | grep -i "ai\|chat\|message\|response\|assistant" | grep -v "node_modules" | head -5 || true)
  fi
}

scan_error_handling() {
  local dir="$1" label="$2"
  log "Scanning $label for exceptional condition handling (A10:2025)..."

  # Fail-open patterns — catch blocks that don't re-throw or handle
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "MEDIUM" "FAIL_OPEN" "${file#$REPO_ROOT/}:$line" "Empty or comment-only catch block — may fail open"
  done < <(grep -rn -A1 "catch\s*(" --include="*.ts" --include="*.tsx" "$dir" 2>/dev/null | grep -B1 "^\s*}\|^\s*//\|^\s*$" | grep "catch" | grep -v "node_modules" | head -10 || true)

  # Stack trace exposure in production
  while IFS=: read -r file line content; do
    [ -z "$file" ] && continue
    finding "MEDIUM" "STACK_EXPOSURE" "${file#$REPO_ROOT/}:$line" "Error stack trace may be exposed in response"
  done < <(grep -rn "error\.\(stack\|message\)" --include="*.ts" "$dir" 2>/dev/null | grep -i "response\|send\|json\|throw.*Http" | grep -v "node_modules" | grep -v "logger\|log\.\|pino" | head -10 || true)
}

# ─── Execute Scans ───────────────────────────────────────────

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║  Security Scanner                         ║"
echo "  ║  Target: $TARGET"
echo "  ╚══════════════════════════════════════════╝"
echo ""

if [ -n "$BE_DIR" ]; then
  log "Detected backend: $BE_NAME"
fi
if [ -n "$FE_DIR" ]; then
  log "Detected frontend: $FE_NAME"
fi
if [ -n "$MOBILE_DIR" ]; then
  log "Detected mobile: $MOBILE_NAME"
fi
echo ""

if [[ "$TARGET" == "backend" || "$TARGET" == "all" ]]; then
  log ""
  if [ -z "$BE_SRC" ]; then
    log "[skip] No backend source directory detected — set BE_DIR env var"
  else
    log "═══ Backend ($BE_NAME) ═══"
    scan_hardcoded_secrets "$BE_SRC" "backend"
    scan_auth_guards "$BE_SRC"
    scan_injection_risks "$BE_SRC" "backend"
    scan_sensitive_logging "$BE_SRC" "backend"
    scan_unsafe_cors "$BE_SRC"
    scan_unsafe_csp "$BE_SRC"
    scan_error_handling "$BE_SRC" "backend"
    scan_deps "$BE_DIR" "$BE_NAME"
    scan_supply_chain "$BE_DIR" "$BE_NAME"
  fi
fi

if [[ "$TARGET" == "frontend" || "$TARGET" == "all" ]]; then
  log ""
  if [ -z "$FE_SRC" ]; then
    log "[skip] No frontend source directory detected — set FE_DIR env var"
  else
    log "═══ Frontend ($FE_NAME) ═══"
    scan_hardcoded_secrets "$FE_SRC" "frontend"
    scan_injection_risks "$FE_SRC" "frontend"
    scan_sensitive_logging "$FE_SRC" "frontend"
    scan_env_exposure "$FE_SRC" "frontend"
    scan_error_handling "$FE_SRC" "frontend"
    scan_deps "$FE_DIR" "$FE_NAME"
    scan_supply_chain "$FE_DIR" "$FE_NAME"
  fi
fi

if [[ "$TARGET" == "mobile" || "$TARGET" == "all" ]]; then
  log ""
  if [ -z "$MOBILE_SRC" ] || [ ! -d "$MOBILE_SRC" ]; then
    log "[skip] No mobile source directory detected — set MOBILE_DIR env var"
  else
    log "═══ Mobile ($MOBILE_NAME) ═══"
    scan_hardcoded_secrets "$MOBILE_SRC" "mobile"
    scan_injection_risks "$MOBILE_SRC" "mobile"
    scan_sensitive_logging "$MOBILE_SRC" "mobile"
    scan_error_handling "$MOBILE_SRC" "mobile"
    scan_deps "$MOBILE_DIR" "$MOBILE_NAME"
    scan_supply_chain "$MOBILE_DIR" "$MOBILE_NAME"
  fi
fi

if [[ "$TARGET" == "supply-chain" || "$TARGET" == "all" ]]; then
  log ""
  log "═══ Supply Chain Analysis ═══"
  [ -n "$BE_DIR" ] && scan_supply_chain "$BE_DIR" "$BE_NAME"
  [ -n "$FE_DIR" ] && scan_supply_chain "$FE_DIR" "$FE_NAME"
  [ -n "$MOBILE_DIR" ] && scan_supply_chain "$MOBILE_DIR" "$MOBILE_NAME"
fi

if [[ "$TARGET" == "llm" || "$TARGET" == "all" ]]; then
  log ""
  log "═══ LLM/AI Agent Security (OWASP LLM Top 10) ═══"
  if [ -n "$BE_SRC" ] && [ -d "$BE_SRC" ]; then
    scan_llm_security "$BE_SRC"
  else
    log "[skip] No backend source directory for LLM scan"
  fi
fi

if [[ "$TARGET" == "secrets" ]]; then
  log ""
  log "═══ Comprehensive Credential Scan (100+ patterns) ═══"
  if [ -x "$SCRIPT_DIR/credential-scanner.sh" ]; then
    "$SCRIPT_DIR/credential-scanner.sh" "$REPO_ROOT" --format text --severity all
  else
    log "Running inline credential scan..."
    [ -n "$BE_SRC" ] && scan_hardcoded_secrets "$BE_SRC" "backend"
    [ -n "$FE_SRC" ] && scan_hardcoded_secrets "$FE_SRC" "frontend"
    [ -n "$MOBILE_SRC" ] && [ -d "$MOBILE_SRC" ] && scan_hardcoded_secrets "$MOBILE_SRC" "mobile"
  fi
fi

# ─── Generate Report ─────────────────────────────────────────
log ""
log "═══ Generating Report ═══"

FINDINGS_JSON=$(printf '%s\n' "${FINDINGS[@]}" | paste -sd ',' - 2>/dev/null || echo "")
cat > "$REPORT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "summary": {
    "critical": $CRITICAL,
    "high": $HIGH,
    "medium": $MEDIUM,
    "low": $LOW,
    "total": $((CRITICAL + HIGH + MEDIUM + LOW))
  },
  "findings": [${FINDINGS_JSON}]
}
EOF

log "Report saved to $REPORT"

# ─── Summary ─────────────────────────────────────────────────
TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))

echo ""
echo "  ════════════════════════════════════════════"
echo "  Security Scan Results"
echo "  ────────────────────"
echo "    🔴 Critical: $CRITICAL"
echo "    🟠 High:     $HIGH"
echo "    🟡 Medium:   $MEDIUM"
echo "    🟢 Low:      $LOW"
echo "    Total:       $TOTAL findings"
echo "  ════════════════════════════════════════════"

if [ $CRITICAL -gt 0 ]; then
  echo ""
  echo "  ⚠️  CRITICAL issues found — fix immediately!"
  exit 2
elif [ $HIGH -gt 0 ]; then
  echo ""
  echo "  ⚠️  HIGH issues found — fix before next release"
  exit 1
else
  echo ""
  echo "  ✅  No critical/high issues found"
fi

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Code Review — Automated Checks
#
# Runs ESLint, TypeScript type-check, and test suite against
# the specified target (backend, frontend, or both).
# Auto-detects project directories from the repo root.
#
# Usage:
#   ./run-review.sh backend          # lint + test backend only
#   ./run-review.sh frontend         # lint + type-check + test frontend only
#   ./run-review.sh all              # both
#   ./run-review.sh backend --fix    # auto-fix lint issues
#
# Environment variables (override auto-detection):
#   BE_DIR=./my-backend  FE_DIR=./my-frontend  ./run-review.sh all
#
# Output: JSON report at ./review-output/review-report.json
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../../.." && pwd)"

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

BE_DIR="${BE_DIR:-$(detect_dir backend backend be-* server api apps/api apps/backend)}"
FE_DIR="${FE_DIR:-$(detect_dir frontend frontend web-* client apps/web apps/frontend)}"

OUTPUT_DIR="$SCRIPT_DIR/../review-output"
REPORT="$OUTPUT_DIR/review-report.json"

TARGET="${1:-all}"
FIX_FLAG="${2:-}"

mkdir -p "$OUTPUT_DIR"

# ─── Helpers ─────────────────────────────────────────────────
log()  { echo "  [review] $*"; }
warn() { echo "  [warn]   $*"; }
ok()   { echo "  [ok]     $*"; }
fail() { echo "  [fail]   $*"; }

run_check() {
  local name="$1"
  local dir="$2"
  shift 2
  local cmd=("$@")

  log "Running $name..."
  local start_ms
  start_ms=$(date +%s%3N 2>/dev/null || date +%s)

  local output exit_code=0
  output=$( cd "$dir" && "${cmd[@]}" 2>&1 ) || exit_code=$?

  local end_ms
  end_ms=$(date +%s%3N 2>/dev/null || date +%s)
  local duration_ms=$(( end_ms - start_ms ))

  if [ $exit_code -eq 0 ]; then
    ok "$name passed (${duration_ms}ms)"
  else
    fail "$name failed (exit $exit_code, ${duration_ms}ms)"
  fi

  # Append to results array
  RESULTS+=("{\"check\":\"$name\",\"exit_code\":$exit_code,\"duration_ms\":$duration_ms,\"output\":$(echo "$output" | head -100 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""')}")
}

RESULTS=()

# ─── Backend Checks ──────────────────────────────────────────
if [[ "$TARGET" == "backend" || "$TARGET" == "all" ]]; then
  log ""
  if [ -z "$BE_DIR" ]; then
    warn "No backend directory detected — set BE_DIR or ensure a backend/ directory exists"
  else
    log "═══ Backend ($(basename "$BE_DIR")) ═══"

    if [ -d "$BE_DIR/node_modules" ]; then
      if [[ "$FIX_FLAG" == "--fix" ]]; then
        run_check "backend-lint-fix" "$BE_DIR" npx eslint "{src,apps,libs,test}/**/*.ts" --fix
      else
        run_check "backend-lint" "$BE_DIR" npx eslint "{src,apps,libs,test}/**/*.ts" --max-warnings 50
      fi

      run_check "backend-test" "$BE_DIR" npx jest --config jest.config.cjs --passWithNoTests --silent
    else
      warn "Backend node_modules not found — run 'npm install' in $(basename "$BE_DIR")/ first"
      RESULTS+=("{\"check\":\"backend-deps\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"node_modules not found\"}")
    fi
  fi
fi

# ─── Frontend Checks ─────────────────────────────────────────
if [[ "$TARGET" == "frontend" || "$TARGET" == "all" ]]; then
  log ""
  if [ -z "$FE_DIR" ]; then
    warn "No frontend directory detected — set FE_DIR or ensure a frontend/ directory exists"
  else
    log "═══ Frontend ($(basename "$FE_DIR")) ═══"

    if [ -d "$FE_DIR/node_modules" ]; then
      if [[ "$FIX_FLAG" == "--fix" ]]; then
        run_check "frontend-lint-fix" "$FE_DIR" npx next lint --fix
      else
        run_check "frontend-lint" "$FE_DIR" npx next lint
      fi

      run_check "frontend-typecheck" "$FE_DIR" npx tsc --noEmit

      run_check "frontend-test" "$FE_DIR" npx jest --passWithNoTests --silent
    else
      warn "Frontend node_modules not found — run 'npm install' in $(basename "$FE_DIR")/ first"
      RESULTS+=("{\"check\":\"frontend-deps\",\"exit_code\":1,\"duration_ms\":0,\"output\":\"node_modules not found\"}")
    fi
  fi
fi

# ─── Generate Report ─────────────────────────────────────────
log ""
log "═══ Generating Report ═══"

RESULTS_JSON=$(printf '%s\n' "${RESULTS[@]}" | paste -sd ',' -)
cat > "$REPORT" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "target": "$TARGET",
  "repo_root": "$REPO_ROOT",
  "checks": [$RESULTS_JSON]
}
EOF

ok "Report saved to $REPORT"

# ─── Summary ─────────────────────────────────────────────────
TOTAL=${#RESULTS[@]}
PASSED=0
for r in "${RESULTS[@]}"; do
  if echo "$r" | grep -q '"exit_code":0'; then
    PASSED=$((PASSED + 1))
  fi
done
FAILED=$((TOTAL - PASSED))

log ""
log "════════════════════════════════"
log "  Results: $PASSED/$TOTAL passed"
if [ $FAILED -gt 0 ]; then
  fail "  $FAILED check(s) failed"
  exit 1
else
  ok "  All checks passed!"
fi

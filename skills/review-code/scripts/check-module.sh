#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Module Health Check
#
# Quickly audit a single NestJS feature module for completeness:
#   - Has module.ts, controller.ts, service.ts?
#   - Has DTOs with validation decorators?
#   - Has Mongoose schemas with proper decorators?
#   - Has tests?
#   - Has Swagger decorators?
#   - Uses auth guards?
#
# Auto-detects backend directory from repo root.
#
# Usage:
#   ./check-module.sh item
#   ./check-module.sh auth
#
# Environment variables (override auto-detection):
#   BE_SRC=./my-backend/src  ./check-module.sh item
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../../../../.." && pwd)"

# ─── Auto-detect backend src directory ────────────────────────
if [ -z "${BE_SRC:-}" ]; then
  for candidate in backend be-* server api apps/api apps/backend; do
    if [ -d "$REPO_ROOT/$candidate/src" ]; then
      BE_SRC="$REPO_ROOT/$candidate/src"
      break
    fi
  done
fi

if [ -z "${BE_SRC:-}" ]; then
  echo "  [error] No backend src directory found. Set BE_SRC env var."
  exit 1
fi

MODULE_NAME="${1:?Usage: check-module.sh <module-name>}"

# Try to find the module directory
MODULE_DIR=""
for candidate in "$BE_SRC/features/$MODULE_NAME" "$BE_SRC/core/$MODULE_NAME"; do
  if [ -d "$candidate" ]; then
    MODULE_DIR="$candidate"
    break
  fi
done

if [ -z "$MODULE_DIR" ]; then
  echo "  [error] Module '$MODULE_NAME' not found in features/ or core/"
  echo "  Available feature modules:"
  ls -1 "$BE_SRC/features/" 2>/dev/null | sed 's/^/    /'
  exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║  Module Health Check: $MODULE_NAME"
echo "  ║  Path: ${MODULE_DIR#$REPO_ROOT/}"
echo "  ╚══════════════════════════════════════╝"
echo ""

ISSUES=0
WARNINGS=0

check() {
  local label="$1" result="$2"
  if [ "$result" == "pass" ]; then
    echo "  ✓  $label"
  elif [ "$result" == "warn" ]; then
    echo "  ⚠  $label"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "  ✗  $label"
    ISSUES=$((ISSUES + 1))
  fi
}

# ─── Structure Checks ────────────────────────────────────────
echo "  Structure:"

# Module file
if find "$MODULE_DIR" -name "*.module.ts" | grep -q .; then
  check "Has module.ts" "pass"
else
  check "Missing module.ts" "fail"
fi

# Controller
if find "$MODULE_DIR" -name "*.controller.ts" | grep -q .; then
  check "Has controller(s)" "pass"
else
  check "No controllers found" "warn"
fi

# Service
if find "$MODULE_DIR" -name "*.service.ts" | grep -q .; then
  check "Has service(s)" "pass"
else
  check "No services found" "warn"
fi

echo ""
echo "  Schemas & DTOs:"

# DTOs
DTO_COUNT=$(find "$MODULE_DIR" -path "*/dto/*" -name "*.ts" 2>/dev/null | wc -l | tr -d ' ')
if [ "$DTO_COUNT" -gt 0 ]; then
  check "Has DTOs ($DTO_COUNT files)" "pass"

  # Check for class-validator usage
  VALIDATED=$(grep -rl "class-validator" "$MODULE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$VALIDATED" -gt 0 ]; then
    check "Uses class-validator decorators" "pass"
  else
    check "DTOs exist but no class-validator decorators found" "warn"
  fi
else
  check "No DTO directory" "warn"
fi

# Entities/Schemas
ENTITY_COUNT=$(find "$MODULE_DIR" -path "*/entities/*" -name "*.ts" 2>/dev/null | wc -l | tr -d ' ')
SCHEMA_COUNT=$(grep -rl "@Schema" "$MODULE_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$ENTITY_COUNT" -gt 0 ] || [ "$SCHEMA_COUNT" -gt 0 ]; then
  check "Has Mongoose schemas ($ENTITY_COUNT entity files, $SCHEMA_COUNT @Schema)" "pass"

  # Check for indexes
  INDEX_COUNT=$(grep -r "@Index\|index: true" "$MODULE_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$INDEX_COUNT" -gt 0 ]; then
    check "Has database indexes ($INDEX_COUNT)" "pass"
  else
    check "No @Index or index:true found — may need indexes for query performance" "warn"
  fi
else
  check "No entity/schema files" "warn"
fi

echo ""
echo "  Quality:"

# Tests
TEST_COUNT=$(find "$MODULE_DIR" -name "*.spec.ts" -o -name "*.test.ts" 2>/dev/null | wc -l | tr -d ' ')
if [ "$TEST_COUNT" -gt 0 ]; then
  check "Has tests ($TEST_COUNT files)" "pass"
else
  check "No test files found" "warn"
fi

# Swagger decorators
SWAGGER_COUNT=$(grep -r "@ApiTags\|@ApiOperation\|@ApiResponse" "$MODULE_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$SWAGGER_COUNT" -gt 0 ]; then
  check "Has Swagger docs ($SWAGGER_COUNT decorators)" "pass"
else
  check "No Swagger decorators found" "warn"
fi

# Auth guards
GUARD_COUNT=$(grep -r "UseGuards\|JwtAuthGuard\|AuthGuard" "$MODULE_DIR" 2>/dev/null | wc -l | tr -d ' ')
if [ "$GUARD_COUNT" -gt 0 ]; then
  check "Uses auth guards ($GUARD_COUNT)" "pass"
else
  check "No auth guards found — are all endpoints public?" "warn"
fi

# any usage
ANY_COUNT=$(grep -r ": any\b" "$MODULE_DIR" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
if [ "$ANY_COUNT" -lt 5 ]; then
  check "Low 'any' usage ($ANY_COUNT occurrences)" "pass"
elif [ "$ANY_COUNT" -lt 20 ]; then
  check "'any' type used $ANY_COUNT times — consider adding proper types" "warn"
else
  check "High 'any' usage ($ANY_COUNT occurrences) — needs typing improvement" "fail"
fi

# Error handling
TRY_CATCH=$(grep -r "try {" "$MODULE_DIR" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
THROWS=$(grep -r "throw new" "$MODULE_DIR" --include="*.ts" 2>/dev/null | wc -l | tr -d ' ')
check "Error handling: $TRY_CATCH try/catch blocks, $THROWS throw statements" "pass"

# File count
TS_COUNT=$(find "$MODULE_DIR" -name "*.ts" | wc -l | tr -d ' ')

echo ""
echo "  ════════════════════════════════════"
echo "  Summary: $TS_COUNT TypeScript files"
echo "  Issues: $ISSUES | Warnings: $WARNINGS"
if [ $ISSUES -gt 0 ]; then
  echo "  Status: NEEDS ATTENTION"
  exit 1
elif [ $WARNINGS -gt 3 ]; then
  echo "  Status: FAIR — several areas for improvement"
else
  echo "  Status: GOOD"
fi
echo ""

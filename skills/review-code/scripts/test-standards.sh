#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Test runner for deep-scan.sh (anti-patterns) and format-check.sh (standards)
#
# Creates synthetic TypeScript fixture files in a temporary repo
# structure, runs both scanners against them, and verifies that
# expected rule names appear in the JSON output.
#
# Both scanners resolve REPO_ROOT as:
#   cd "$SCRIPT_DIR/../../../../.."   (5 directory levels up)
# We mirror that exact depth so REPO_ROOT resolves to $WORK and
# all fixture projects live directly under $WORK.
#
# Directory layout:
#   $WORK/                                       <- REPO_ROOT
#   $WORK/x/skills/skills/review-code/scripts/  <- FAKE_SCRIPTS (5 deep)
#   $WORK/styai-mobile/src/                      <- mobile fixture files
#   $WORK/backend/src/                           <- backend fixture files
#
# Usage:
#   ./test-standards.sh              # run all tests
#   ./test-standards.sh --verbose    # show scanner output for debugging
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed
# ─────────────────────────────────────────────────────────────

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors (disabled when stdout is not a TTY) ───────────────
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BOLD=''
  NC=''
fi

VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=true ;;
  esac
done

# ─── Counters ─────────────────────────────────────────────────
PASS=0
FAIL=0
FAILURES=()

# ─────────────────────────────────────────────────────────────
# TEMP DIRECTORY STRUCTURE
#
# The scanners compute REPO_ROOT via:
#   cd "$SCRIPT_DIR/../../../../.."
# Placing scripts 5 levels deep under $WORK makes REPO_ROOT = $WORK.
# ─────────────────────────────────────────────────────────────
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAKE_SCRIPTS="$WORK/x/skills/skills/review-code/scripts"
mkdir -p "$FAKE_SCRIPTS"

MB_PROJECT="$WORK/styai-mobile"
BE_PROJECT="$WORK/backend"
MB_SRC="$MB_PROJECT/src"
BE_SRC="$BE_PROJECT/src"
mkdir -p "$MB_SRC" "$BE_SRC"

# ─── Copy scripts into temp location ─────────────────────────
cp "$SCRIPT_DIR/deep-scan.sh"    "$FAKE_SCRIPTS/deep-scan.sh"
cp "$SCRIPT_DIR/format-check.sh" "$FAKE_SCRIPTS/format-check.sh"
chmod +x "$FAKE_SCRIPTS/deep-scan.sh" "$FAKE_SCRIPTS/format-check.sh"

# ─────────────────────────────────────────────────────────────
# FIXTURE FILES
# ─────────────────────────────────────────────────────────────

# ── test-anti-patterns.ts ─────────────────────────────────────
# Triggers: empty_catch, console_usage, as_any,
#           todo_without_ticket, magic_number, deep_nesting
cat > "$MB_SRC/test-anti-patterns.ts" << 'FIXTURE'
// ── empty catch block ─────────────────────────────────────────
async function loadData() {
  try {
    const result = await fetch('/api/data');
    return result;
  } catch (err) {
  }
}

// ── console.log in production code ───────────────────────────
function debugUser(user: unknown) {
  console.log('fetching user', user);
  console.warn('user might be stale');
  return user;
}

// ── as any type assertion ─────────────────────────────────────
function coerce(val: unknown) {
  return val as any;
}

// ── TODO/FIXME/HACK without ticket reference ──────────────────
// TODO: fix this properly
// FIXME: remove this workaround
// HACK: bypass validation

// ── magic numbers (2+ digit literal in expression) ────────────
function retry(fn: () => void) {
  const LIMIT = 42;
  for (let attempt = 0; attempt < LIMIT; attempt++) {
    if (attempt === 10) fn();
  }
}

// ── deep nesting (6 levels) ───────────────────────────────────
function processOrder(order: unknown) {
  if (order) {
    if ((order as any).items) {
      for (const item of (order as any).items) {
        if (item.available) {
          while (item.qty > 0) {
            if (item.price > 0) {
              // 6 levels deep — triggers deep_nesting rule
            }
          }
        }
      }
    }
  }
}
FIXTURE

# ── test-smells.ts ────────────────────────────────────────────
# Triggers: hardcoded_url, hardcoded_email, commented_code, generic_name
cat > "$MB_SRC/test-smells.ts" << 'FIXTURE'
// ── hardcoded production URL ──────────────────────────────────
const endpoint = 'https://api.production.mycompany.com/v2/items';

// ── hardcoded email address ───────────────────────────────────
const adminContact = 'admin@mycompany.com';

// ── generic variable names ────────────────────────────────────
function handleResponse() {
  const data = fetchItems();
  const result = processData(data);
  const temp = transform(result);
  return temp;
}

// ── 4 consecutive commented-out code lines (threshold: 3) ─────
// import { OldService } from './old-service';
// import { LegacyHelper } from './legacy';
// import { DeprecatedUtil } from './utils';
// const helper = new LegacyHelper();

function fetchItems() { return []; }
function processData(x: unknown) { return x; }
function transform(x: unknown) { return x; }
FIXTURE

# ── test-naming.ts ────────────────────────────────────────────
# Triggers: single_letter_var, generic_name
cat > "$MB_SRC/test-naming.ts" << 'FIXTURE'
// ── single-letter variables outside loops ─────────────────────
const a = getUserName();
const b = getProfile();

// ── generic variable names ────────────────────────────────────
const val = computeTotal();
const obj = buildConfig();
const info = loadMetadata();

function getUserName() { return 'alice'; }
function getProfile() { return {}; }
function computeTotal() { return 0; }
function buildConfig() { return {}; }
function loadMetadata() { return {}; }
FIXTURE

# ── test-bloaters.ts ──────────────────────────────────────────
# Triggers: long_function (body > 30 lines, threshold MAX_FUNC_LINES=30)
cat > "$MB_SRC/test-bloaters.ts" << 'FIXTURE'
function veryLongProcessing(input: string): string {
  const step01 = input.trim();
  const step02 = step01.toLowerCase();
  const step03 = step02.replace(/\s+/g, '-');
  const step04 = step03.replace(/[^a-z0-9-]/g, '');
  const step05 = step04.replace(/--+/g, '-');
  const step06 = step05.replace(/^-|-$/g, '');
  const step07 = step06.split('-');
  const step08 = step07.filter(Boolean);
  const step09 = step08.join('-');
  const step10 = step09.substring(0, 100);
  const step11 = step10 || 'untitled';
  const step12 = step11.padEnd(10, '-');
  const step13 = step12.slice(0, 50);
  const step14 = step13 + '-end';
  const step15 = step14.toUpperCase();
  const step16 = step15.replace('END', 'fin');
  const step17 = step16.trim();
  const step18 = step17.replace(/-$/, '');
  const step19 = step18.toLowerCase();
  const step20 = step19 || 'default-slug';
  const step21 = step20.split('');
  const step22 = step21.reverse();
  const step23 = step22.join('');
  const step24 = step23.substring(0, 80);
  const step25 = step24.trim();
  const step26 = step25 || 'fallback';
  const step27 = step26.toUpperCase();
  const step28 = step27.toLowerCase();
  const step29 = step28.replace(/\s/g, '_');
  const step30 = step29 || 'slug';
  const step31 = step30 + '-done';
  return step31;
}
FIXTURE

# ── test-format-imports.ts ────────────────────────────────────
# Triggers: import_order (external after relative), wildcard_import
cat > "$MB_SRC/test-format-imports.ts" << 'FIXTURE'
import { useState } from 'react';
import { useRouter } from 'next/router';
import { formatDate } from './utils';
import { UserService } from './services/user';
import axios from 'axios';
import * as helpers from './helpers';
FIXTURE

# ── test-format-patterns.ts ───────────────────────────────────
# Triggers: mixed_exports, mixed_async_patterns, string_concat
cat > "$MB_SRC/test-format-patterns.ts" << 'FIXTURE'
export const CONSTANT_ONE = 'value';
export const CONSTANT_TWO = 42;
export const CONSTANT_THREE = true;

export default function mainExport() { return null; }

async function fetchAll() {
  const a = await fetchOne('a');
  const b = await fetchTwo('b');
  const c = await fetchThree('c');
  fetchOne('x').then(handleX).catch(errX);
  fetchTwo('y').then(handleY).catch(errY);
  fetchThree('z').then(handleZ).catch(errZ);
  return [a, b, c];
}

function greet(name: string) {
  return 'Hello, ' + name + '! Welcome.';
}

function fetchOne(x: string) { return Promise.resolve(x); }
function fetchTwo(x: string) { return Promise.resolve(x); }
function fetchThree(x: string) { return Promise.resolve(x); }
function handleX(_x: unknown) {}
function handleY(_x: unknown) {}
function handleZ(_x: unknown) {}
function errX(_e: unknown) {}
function errY(_e: unknown) {}
function errZ(_e: unknown) {}
FIXTURE

# ── camelCaseFile.ts ──────────────────────────────────────────
# Triggers: camelcase_filename
cat > "$MB_SRC/camelCaseFile.ts" << 'FIXTURE'
export const placeholder = 1;
FIXTURE

# ── Backend: fat controller ───────────────────────────────────
# Triggers: fat_controller (direct DB operations in a .controller.ts)
mkdir -p "$BE_SRC/features/order"
cat > "$BE_SRC/features/order/order.controller.ts" << 'FIXTURE'
import { Controller, Get } from '@nestjs/common';

@Controller('orders')
export class OrderController {
  constructor(private readonly orderModel: any) {}

  @Get()
  async findAll() {
    return this.orderModel.find({ status: 'active' });
  }

  @Get(':id')
  async findOne(id: string) {
    return this.orderModel.findOne({ _id: id });
  }
}
FIXTURE

# ── Backend: DIP violation ────────────────────────────────────
# Triggers: dip_violation (new Service() in non-test file)
cat > "$BE_SRC/features/order/order.service.ts" << 'FIXTURE'
import { Injectable } from '@nestjs/common';

@Injectable()
export class OrderService {
  private readonly emailService = new EmailService();
  private readonly pdfService = new PdfService();

  async processOrder(id: string) {
    return { id };
  }
}

class EmailService {}
class PdfService {}
FIXTURE

# ── Config files for format-check ────────────────────────────
# package.json is required by detect_root() in format-check.sh
cat > "$MB_PROJECT/package.json" << 'FIXTURE'
{ "name": "styai-mobile", "version": "1.0.0" }
FIXTURE

# strict: false triggers ts_not_strict
cat > "$MB_PROJECT/tsconfig.json" << 'FIXTURE'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "strict": false,
    "esModuleInterop": true
  }
}
FIXTURE

cat > "$BE_PROJECT/package.json" << 'FIXTURE'
{ "name": "backend", "version": "1.0.0" }
FIXTURE

# No strict setting — triggers ts_not_strict (missing = not strict)
cat > "$BE_PROJECT/tsconfig.json" << 'FIXTURE'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "esModuleInterop": true
  }
}
FIXTURE
# Note: no .prettierignore or .editorconfig created, so those rules fire

# ─────────────────────────────────────────────────────────────
# ASSERTION HELPERS
# ─────────────────────────────────────────────────────────────

assert_finding() {
  local label="$1" rule="$2" output="$3"
  if echo "$output" | grep -q "\"rule\":\"$rule\""; then
    echo -e "  ${GREEN}PASS${NC}  $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}  $label"
    echo -e "        Expected rule '${YELLOW}$rule${NC}' not found in output"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label: expected rule '$rule'")
  fi
}

assert_no_finding() {
  local label="$1" rule="$2" output="$3"
  if echo "$output" | grep -q "\"rule\":\"$rule\""; then
    echo -e "  ${RED}FAIL${NC}  $label"
    echo -e "        Unexpected rule '${YELLOW}$rule${NC}' found in output"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label: unexpected rule '$rule'")
  else
    echo -e "  ${GREEN}PASS${NC}  $label"
    PASS=$((PASS + 1))
  fi
}

assert_json_valid() {
  local label="$1" output="$2"
  if echo "$output" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}  $label"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC}  $label — output is not valid JSON"
    FAIL=$((FAIL + 1))
    FAILURES+=("$label: invalid JSON output")
  fi
}

# ─────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "  ${BOLD}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║  Standards & Anti-Pattern Scanner Test Suite      ║${NC}"
echo -e "  ${BOLD}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Temp root:   $WORK"
echo "  Scripts:     $FAKE_SCRIPTS"
echo "  Mobile src:  $MB_SRC"
echo "  Backend src: $BE_SRC"
echo ""

# ─────────────────────────────────────────────────────────────
# RUN DEEP-SCAN (anti-patterns scanner)
# ─────────────────────────────────────────────────────────────
echo -e "  ${BOLD}── deep-scan.sh (anti-patterns) ────────────────────${NC}"
echo ""

# Allow non-zero exit: scanner exits 1 (warnings) or 2 (critical)
DEEP_OUT=$(bash "$FAKE_SCRIPTS/deep-scan.sh" 2>/dev/null) || true

if [ "$VERBOSE" = true ]; then
  echo "  [deep-scan raw output (first 60 lines)]"
  echo "$DEEP_OUT" | head -60
  echo ""
fi

assert_json_valid \
  "deep-scan produces valid JSON output" \
  "$DEEP_OUT"

# smells
assert_finding \
  "smells: empty_catch — silent exception swallowing" \
  "empty_catch" "$DEEP_OUT"

assert_finding \
  "smells: console_usage — console.log/warn in production code" \
  "console_usage" "$DEEP_OUT"

assert_finding \
  "smells: as_any — 'as any' type assertion bypasses TypeScript" \
  "as_any" "$DEEP_OUT"

assert_finding \
  "smells: todo_without_ticket — TODO/FIXME/HACK without issue ref" \
  "todo_without_ticket" "$DEEP_OUT"

assert_finding \
  "smells: hardcoded_url — production URL literal in source" \
  "hardcoded_url" "$DEEP_OUT"

assert_finding \
  "smells: hardcoded_email — email address literal in source" \
  "hardcoded_email" "$DEEP_OUT"

assert_finding \
  "smells: commented_code — 3+ consecutive commented-out lines" \
  "commented_code" "$DEEP_OUT"

assert_finding \
  "smells: magic_number — bare numeric literal in logic" \
  "magic_number" "$DEEP_OUT"

# naming
assert_finding \
  "naming: single_letter_var — non-descriptive one-letter variable" \
  "single_letter_var" "$DEEP_OUT"

assert_finding \
  "naming: generic_name — vague variable name (val/obj/data/temp)" \
  "generic_name" "$DEEP_OUT"

# bloaters
assert_finding \
  "bloaters: long_function — function body exceeds 30-line threshold" \
  "long_function" "$DEEP_OUT"

assert_finding \
  "bloaters: deep_nesting — conditional/loop nesting exceeds level 3" \
  "deep_nesting" "$DEEP_OUT"

# solid
assert_finding \
  "solid: fat_controller — database operations in controller layer" \
  "fat_controller" "$DEEP_OUT"

assert_finding \
  "solid: dip_violation — manual 'new Service()' bypasses DI container" \
  "dip_violation" "$DEEP_OUT"

# negative checks
assert_no_finding \
  "solid: no false-positive self_import (no file imports itself)" \
  "self_import" "$DEEP_OUT"

assert_no_finding \
  "solid: no false-positive service_locator (no moduleRef.get() calls)" \
  "service_locator" "$DEEP_OUT"

echo ""

# ─────────────────────────────────────────────────────────────
# RUN FORMAT-CHECK (standards scanner)
# ─────────────────────────────────────────────────────────────
echo -e "  ${BOLD}── format-check.sh (standards) ─────────────────────${NC}"
echo ""

FORMAT_OUT=$(bash "$FAKE_SCRIPTS/format-check.sh" 2>/dev/null) || true

if [ "$VERBOSE" = true ]; then
  echo "  [format-check raw output (first 60 lines)]"
  echo "$FORMAT_OUT" | head -60
  echo ""
fi

assert_json_valid \
  "format-check produces valid JSON output" \
  "$FORMAT_OUT"

# configs
assert_finding \
  "configs: ts_not_strict — TypeScript strict mode is disabled" \
  "ts_not_strict" "$FORMAT_OUT"

assert_finding \
  "configs: missing_prettierignore — no .prettierignore in project root" \
  "missing_prettierignore" "$FORMAT_OUT"

assert_finding \
  "configs: missing_editorconfig — no .editorconfig in project or repo root" \
  "missing_editorconfig" "$FORMAT_OUT"

# imports
assert_finding \
  "imports: import_order — external import appears after relative import" \
  "import_order" "$FORMAT_OUT"

assert_finding \
  "imports: wildcard_import — 'import * as' prevents tree-shaking" \
  "wildcard_import" "$FORMAT_OUT"

# naming
assert_finding \
  "naming: camelcase_filename — file uses camelCase instead of kebab-case" \
  "camelcase_filename" "$FORMAT_OUT"

# patterns
assert_finding \
  "patterns: mixed_exports — default export alongside 3+ named exports" \
  "mixed_exports" "$FORMAT_OUT"

assert_finding \
  "patterns: mixed_async_patterns — .then() and async/await used in same file" \
  "mixed_async_patterns" "$FORMAT_OUT"

assert_finding \
  "patterns: string_concat — '+' on string literals (prefer template literal)" \
  "string_concat" "$FORMAT_OUT"

# negative checks
# .controller.ts is explicitly whitelisted in format-check.sh naming check
assert_no_finding \
  "naming: no false-positive pascalcase_non_component on .controller.ts" \
  "pascalcase_non_component" "$FORMAT_OUT"

# No eslint config files in temp repo, so no drift can be detected
assert_no_finding \
  "configs: no false-positive eslint_format_drift (no eslint configs present)" \
  "eslint_format_drift" "$FORMAT_OUT"

echo ""

# ─────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────
TOTAL=$((PASS + FAIL))

echo -e "  ${BOLD}════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo -e "  Total:   $TOTAL"
echo -e "  ${BOLD}════════════════════════════════════════════════════${NC}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "  ${RED}${BOLD}Failed assertions:${NC}"
  for f in "${FAILURES[@]}"; do
    echo "    - $f"
  done
  echo ""
  echo -e "  ${RED}${FAIL} test(s) failed.${NC}"
  exit 1
else
  echo ""
  echo -e "  ${GREEN}All $PASS tests passed.${NC}"
  exit 0
fi

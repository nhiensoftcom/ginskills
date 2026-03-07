#!/bin/bash
# Flutter Performance Anti-Pattern Scanner
# Usage: ./flutter-perf-scan.sh [project-path] [category]
# Categories: all, rebuilds, memory, images, lists, state, size

set -euo pipefail

PROJECT_PATH="${1:-.}"
CATEGORY="${2:-all}"
FOUND=0
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

RED='\033[0;31m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

report() {
  local severity="$1"
  local title="$2"
  local file="$3"
  local detail="$4"
  FOUND=$((FOUND + 1))
  case "$severity" in
    CRITICAL) CRITICAL=$((CRITICAL + 1)); echo -e "${RED}[CRITICAL]${NC} $title" ;;
    HIGH)     HIGH=$((HIGH + 1));         echo -e "${ORANGE}[HIGH]${NC} $title" ;;
    MEDIUM)   MEDIUM=$((MEDIUM + 1));     echo -e "${YELLOW}[MEDIUM]${NC} $title" ;;
    LOW)      LOW=$((LOW + 1));           echo -e "${GREEN}[LOW]${NC} $title" ;;
  esac
  echo "  File: $file"
  echo "  $detail"
  echo ""
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Flutter Performance Anti-Pattern Scan${NC}"
echo -e "${CYAN}========================================${NC}"
echo "Project: $PROJECT_PATH"
echo "Category: $CATEGORY"
echo ""

# Verify it's a Flutter project
if [ ! -f "$PROJECT_PATH/pubspec.yaml" ]; then
  echo -e "${RED}Error: No pubspec.yaml found at $PROJECT_PATH${NC}"
  exit 1
fi

LIB_PATH="$PROJECT_PATH/lib"
if [ ! -d "$LIB_PATH" ]; then
  echo -e "${RED}Error: No lib/ directory found${NC}"
  exit 1
fi

# ── Category: Widget Rebuilds ──────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "rebuilds" ]]; then
  echo -e "${CYAN}── Checking Widget Rebuild Patterns ──${NC}"
  echo ""

  # Missing const on common static widgets
  while IFS= read -r line; do
    file=$(echo "$line" | cut -d: -f1)
    report "MEDIUM" "Missing const on static widget" "$line" \
      "Fix: Add 'const' keyword. Reduces unnecessary rebuilds by up to 70%."
  done < <(grep -rn "^\s*Text(['\"]" "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -v "const " | head -20 || true)

  while IFS= read -r line; do
    report "MEDIUM" "Missing const on Icon widget" "$line" \
      "Fix: Use 'const Icon(Icons.xxx)' for static icons."
  done < <(grep -rn "^\s*Icon(Icons\." "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -v "const " | head -10 || true)

  while IFS= read -r line; do
    report "MEDIUM" "Missing const on SizedBox" "$line" \
      "Fix: Use 'const SizedBox(...)' for static spacing."
  done < <(grep -rn "^\s*SizedBox(" "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -v "const " | head -10 || true)

  # Inline anonymous functions in build (causing rebuilds)
  while IFS= read -r line; do
    report "HIGH" "Inline onPressed callback may cause child rebuilds" "$line" \
      "Fix: Extract callback to a method or use tear-off. Inline closures create new instances each build."
  done < <(grep -rn "onPressed: () =>" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)

  while IFS= read -r line; do
    report "HIGH" "Inline onTap callback may cause child rebuilds" "$line" \
      "Fix: Extract callback to a method or use tear-off."
  done < <(grep -rn "onTap: () =>" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)
fi

# ── Category: Memory Leaks ─────────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "memory" ]]; then
  echo -e "${CYAN}── Checking Memory Leak Patterns ──${NC}"
  echo ""

  # TextEditingController without dispose
  while IFS= read -r file; do
    if ! grep -q "\.dispose()" "$file" 2>/dev/null; then
      report "CRITICAL" "TextEditingController without dispose()" "$file" \
        "Fix: Add controller.dispose() in the dispose() method. Memory leak guaranteed."
    fi
  done < <(grep -rl "TextEditingController()" "$LIB_PATH" --include="*.dart" 2>/dev/null || true)

  # ScrollController without dispose
  while IFS= read -r file; do
    if ! grep -q "\.dispose()" "$file" 2>/dev/null; then
      report "CRITICAL" "ScrollController without dispose()" "$file" \
        "Fix: Add scrollController.dispose() in the dispose() method."
    fi
  done < <(grep -rl "ScrollController()" "$LIB_PATH" --include="*.dart" 2>/dev/null || true)

  # AnimationController without dispose
  while IFS= read -r file; do
    if ! grep -q "\.dispose()" "$file" 2>/dev/null; then
      report "CRITICAL" "AnimationController without dispose()" "$file" \
        "Fix: Add controller.dispose() in the dispose() method."
    fi
  done < <(grep -rl "AnimationController(" "$LIB_PATH" --include="*.dart" 2>/dev/null || true)

  # Stream subscriptions without cancel
  while IFS= read -r file; do
    if ! grep -q "\.cancel()" "$file" 2>/dev/null; then
      report "HIGH" "Stream .listen() without .cancel()" "$file" \
        "Fix: Store the StreamSubscription and cancel it in dispose()."
    fi
  done < <(grep -rl "\.listen(" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)

  # Timer without cancel
  while IFS= read -r file; do
    if ! grep -q "\.cancel()" "$file" 2>/dev/null; then
      report "HIGH" "Timer without cancel()" "$file" \
        "Fix: Cancel the timer in dispose() to prevent leaks."
    fi
  done < <(grep -rl "Timer\.\|Timer(" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)
fi

# ── Category: Images ───────────────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "images" ]]; then
  echo -e "${CYAN}── Checking Image Patterns ──${NC}"
  echo ""

  # Image.network without caching
  while IFS= read -r line; do
    report "HIGH" "Image.network without caching" "$line" \
      "Fix: Use CachedNetworkImage for network images. Image.network re-downloads every time."
  done < <(grep -rn "Image\.network(" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)

  # NetworkImage without caching
  while IFS= read -r line; do
    report "MEDIUM" "NetworkImage without disk caching" "$line" \
      "Fix: Consider CachedNetworkImageProvider for disk caching."
  done < <(grep -rn "NetworkImage(" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)

  # No memCacheWidth/Height on cached images
  while IFS= read -r file; do
    if ! grep -q "memCacheWidth\|memCacheHeight" "$file" 2>/dev/null; then
      if grep -q "CachedNetworkImage" "$file" 2>/dev/null; then
        report "MEDIUM" "CachedNetworkImage without memCacheWidth/Height" "$file" \
          "Fix: Add memCacheWidth/memCacheHeight to decode at display size, not full resolution."
      fi
    fi
  done < <(grep -rl "CachedNetworkImage" "$LIB_PATH" --include="*.dart" 2>/dev/null || true)

  # Large asset images (PNG)
  LARGE_PNGS=$(find "$PROJECT_PATH/assets" -name "*.png" -size +500k 2>/dev/null | head -5 || true)
  if [ -n "$LARGE_PNGS" ]; then
    while IFS= read -r file; do
      SIZE=$(du -h "$file" | cut -f1)
      report "MEDIUM" "Large PNG asset ($SIZE)" "$file" \
        "Fix: Convert to WebP (50-70% smaller): cwebp -q 80 input.png -o output.webp"
    done <<< "$LARGE_PNGS"
  fi
fi

# ── Category: Lists ────────────────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "lists" ]]; then
  echo -e "${CYAN}── Checking List Patterns ──${NC}"
  echo ""

  # ListView with children (not builder)
  while IFS= read -r line; do
    report "HIGH" "ListView with children (not builder)" "$line" \
      "Fix: Use ListView.builder for lazy construction. Current code builds ALL items upfront."
  done < <(grep -rn "ListView(\s*$\|children:" "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -v "ListView\.builder\|ListView\.separated\|ListView\.custom" | head -10 || true)

  # Column + SingleChildScrollView (anti-pattern for long lists)
  while IFS= read -r line; do
    report "MEDIUM" "SingleChildScrollView may indicate list anti-pattern" "$line" \
      "Fix: If wrapping a Column with many items, use ListView.builder instead."
  done < <(grep -rn "SingleChildScrollView" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -5 || true)

  # key: ValueKey(index) — wrong key usage
  while IFS= read -r line; do
    report "HIGH" "Using index as key" "$line" \
      "Fix: Use a stable unique ID as key: ValueKey(item.id). Index keys cause state mismatch on reorder/insert."
  done < <(grep -rn "ValueKey(index)" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -5 || true)
fi

# ── Category: State Management ─────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "state" ]]; then
  echo -e "${CYAN}── Checking State Management Patterns ──${NC}"
  echo ""

  # setState in StreamBuilder/FutureBuilder
  while IFS= read -r file; do
    if grep -q "setState" "$file" 2>/dev/null && grep -q "StreamBuilder\|FutureBuilder" "$file" 2>/dev/null; then
      report "HIGH" "setState used alongside StreamBuilder/FutureBuilder" "$file" \
        "Fix: Let StreamBuilder/FutureBuilder manage state. Using setState causes double rebuilds."
    fi
  done < <(grep -rl "StreamBuilder\|FutureBuilder" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)

  # context.watch without Consumer
  while IFS= read -r line; do
    report "MEDIUM" "context.watch usage (may cause broad rebuilds)" "$line" \
      "Fix: Use Consumer or Selector widget to limit rebuild scope."
  done < <(grep -rn "context\.watch" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -10 || true)
fi

# ── Category: App Size ─────────────────────────────────────────────────

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "size" ]]; then
  echo -e "${CYAN}── Checking App Size Patterns ──${NC}"
  echo ""

  # Check for unused imports (basic check)
  while IFS= read -r line; do
    report "LOW" "Potentially unused import" "$line" \
      "Fix: Remove unused imports. Run 'dart fix --apply' for automatic cleanup."
  done < <(grep -rn "^import.*;" "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -i "unused" | head -5 || true)

  # Count dependencies
  DEP_COUNT=$(grep -c "^\s\s\w" "$PROJECT_PATH/pubspec.yaml" 2>/dev/null || echo "0")
  if [ "$DEP_COUNT" -gt 30 ]; then
    report "MEDIUM" "High dependency count ($DEP_COUNT)" "$PROJECT_PATH/pubspec.yaml" \
      "Fix: Audit dependencies. Each package increases app size. Remove unused packages."
  fi

  # Large asset files
  LARGE_ASSETS=$(find "$PROJECT_PATH/assets" -size +1M 2>/dev/null | head -5 || true)
  if [ -n "$LARGE_ASSETS" ]; then
    while IFS= read -r file; do
      SIZE=$(du -h "$file" | cut -f1)
      report "MEDIUM" "Large asset file ($SIZE)" "$file" \
        "Fix: Compress or resize. Consider WebP for images, optimize SVGs."
    done <<< "$LARGE_ASSETS"
  fi
fi

# ── Category: General Anti-Patterns ────────────────────────────────────

if [[ "$CATEGORY" == "all" ]]; then
  echo -e "${CYAN}── Checking General Anti-Patterns ──${NC}"
  echo ""

  # Opacity widget (should use AnimatedOpacity or color opacity)
  while IFS= read -r line; do
    report "MEDIUM" "Opacity widget creates extra render layer" "$line" \
      "Fix: Use AnimatedOpacity for animations, or Color.withOpacity() for static opacity."
  done < <(grep -rn "^\s*Opacity(" "$LIB_PATH" --include="*.dart" 2>/dev/null | grep -v "AnimatedOpacity" | head -5 || true)

  # Heavy sync operations that should use isolates
  while IFS= read -r line; do
    report "HIGH" "jsonDecode in main isolate (may block UI)" "$line" \
      "Fix: For large payloads, use compute(jsonDecode, rawString) to offload to isolate."
  done < <(grep -rn "jsonDecode(" "$LIB_PATH" --include="*.dart" 2>/dev/null | head -5 || true)

  # print statements (should use debugPrint in Flutter)
  PRINT_COUNT=$(grep -rc "^\s*print(" "$LIB_PATH" --include="*.dart" 2>/dev/null | awk -F: '{sum+=$2} END {print sum}' || echo "0")
  if [ "$PRINT_COUNT" -gt 5 ]; then
    report "LOW" "Found $PRINT_COUNT print() calls" "$LIB_PATH" \
      "Fix: Use debugPrint() instead. print() can cause frame drops due to synchronous I/O."
  fi
fi

# ── Summary ────────────────────────────────────────────────────────────

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Scan Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "Total findings: $FOUND"
echo -e "  ${RED}CRITICAL: $CRITICAL${NC}"
echo -e "  ${ORANGE}HIGH:     $HIGH${NC}"
echo -e "  ${YELLOW}MEDIUM:   $MEDIUM${NC}"
echo -e "  ${GREEN}LOW:      $LOW${NC}"
echo ""

if [ "$FOUND" -eq 0 ]; then
  echo -e "${GREEN}No performance anti-patterns detected. Run DevTools profiling for deeper analysis.${NC}"
fi

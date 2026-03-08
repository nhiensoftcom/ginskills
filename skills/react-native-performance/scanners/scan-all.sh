#!/bin/bash
# React Native Performance — Full Scan Orchestrator
DIR="${1:-./src}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ANSI colors (disabled if not a TTY)
if [ -t 1 ]; then
  RED='\033[0;31m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  GREEN='\033[0;32m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' YELLOW='' CYAN='' GREEN='' BOLD='' RESET=''
fi

echo ""
echo "${BOLD}React Native Performance — Full Codebase Scan${RESET}"
echo "${BOLD}Target: $DIR${RESET}"
echo "================================================="
echo ""

# Temp file to accumulate all output for summary counting
TMPFILE=$(mktemp)

SCANNERS=(
  "rendering:Rendering Performance"
  "memory-leaks:Memory Leaks"
  "bundle-size:Bundle Size"
  "navigation:Navigation"
  "state-network:State & Network"
  "images:Images"
  "animations:Animations"
  "console-devtools:Console & DevTools"
)

for entry in "${SCANNERS[@]}"; do
  name="${entry%%:*}"
  label="${entry##*:}"

  echo "${CYAN}--- [$label] ---${RESET}"

  scanner="$SCRIPT_DIR/scan-$name.sh"

  if [ ! -f "$scanner" ]; then
    echo "${RED}  Scanner not found: $scanner${RESET}"
    echo ""
    continue
  fi

  output=$(bash "$scanner" "$DIR" 2>/dev/null)

  # Print output with color-coded severity
  echo "$output" | while IFS= read -r line; do
    if echo "$line" | grep -q '\[ERROR\]'; then
      echo "${RED}${line}${RESET}"
    elif echo "$line" | grep -q '\[WARN\]'; then
      echo "${YELLOW}${line}${RESET}"
    elif echo "$line" | grep -q '\[INFO\]'; then
      echo "${CYAN}${line}${RESET}"
    else
      echo "$line"
    fi
  done

  # Save output to temp file for counting
  echo "$output" >> "$TMPFILE"

  echo ""
  echo "---"
done

# Summary
echo ""
echo "================================================="
echo "${BOLD}Summary${RESET}"
echo "================================================="

ERRORS=$(grep -c '\[ERROR\]' "$TMPFILE" 2>/dev/null || echo 0)
WARNS=$(grep -c '\[WARN\]'  "$TMPFILE" 2>/dev/null || echo 0)
INFOS=$(grep -c '\[INFO\]'  "$TMPFILE" 2>/dev/null || echo 0)
TOTAL=$((ERRORS + WARNS + INFOS))

echo "${RED}  ERROR : $ERRORS${RESET}"
echo "${YELLOW}  WARN  : $WARNS${RESET}"
echo "${CYAN}  INFO  : $INFOS${RESET}"
echo "${BOLD}  TOTAL : $TOTAL issues found${RESET}"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo "${RED}  Fix ERROR issues first — they directly impact performance or cause crashes.${RESET}"
fi
if [ "$WARNS" -gt 0 ]; then
  echo "${YELLOW}  Then address WARN issues — they degrade performance under load.${RESET}"
fi
if [ "$INFOS" -gt 0 ]; then
  echo "${CYAN}  INFO issues are best-practice improvements worth addressing over time.${RESET}"
fi

echo ""

# Top offending files
echo "${BOLD}Top files by issue count:${RESET}"
grep -oE '^[^:]+:[0-9]+' "$TMPFILE" 2>/dev/null \
  | cut -d: -f1 \
  | sort \
  | uniq -c \
  | sort -rn \
  | head -10 \
  | while IFS= read -r entry; do
      count=$(echo "$entry" | awk '{print $1}')
      file=$(echo "$entry" | awk '{print $2}')
      echo "  $count issues — $file"
    done

rm -f "$TMPFILE"

echo ""
echo "${GREEN}Full scan complete!${RESET}"
echo ""
echo "Priority: Fix ERROR issues first, then WARN, then INFO"
echo "Run individual scanners for focused analysis:"
echo "  bash $SCRIPT_DIR/scan-rendering.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-memory-leaks.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-bundle-size.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-navigation.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-state-network.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-images.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-animations.sh $DIR"
echo "  bash $SCRIPT_DIR/scan-console-devtools.sh $DIR"
echo ""

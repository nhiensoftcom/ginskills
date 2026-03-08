#!/bin/bash
# React Native Rendering Performance Scanner
DIR="${1:-.}"
EXT="--include=*.tsx --include=*.ts --include=*.jsx --include=*.js"
ISSUES=0

echo "Scanning for rendering performance issues in $DIR..."
echo "=================================================="

# 1. Inline arrow functions in JSX event handlers (onPress, onChange, onSubmit, etc.)
# Pattern: onSomeEvent={() => or onSomeEvent={(e) =>
grep -rn $EXT 'on[A-Z][a-zA-Z]*={(\s*)\(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] Inline arrow function in JSX prop → Extract to useCallback"
  ISSUES=$((ISSUES + 1))
done

# 2. Inline style objects: style={{ (but NOT style={styles. or style={[)
grep -rn $EXT 'style={{' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | grep -v 'StyleSheet\|styles\.' | while IFS= read -r line; do
  echo "$line — [WARN] Inline style object → Move to StyleSheet.create"
  ISSUES=$((ISSUES + 1))
done

# 3. key={index} or key={i} in lists/maps
grep -rn $EXT 'key={index}\|key={i}\b' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [ERROR] Using index as key → Use stable unique ID (item.id)"
  ISSUES=$((ISSUES + 1))
done

# 4. FlatList / SectionList inside ScrollView
# Look for files that contain both a virtualized list and ScrollView
grep -rln $EXT 'FlatList\|SectionList\|FlashList' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'ScrollView' "$file"; then
    grep -n '<FlatList\|<SectionList\|<FlashList' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] FlatList/SectionList inside ScrollView → Use ListHeaderComponent/ListFooterComponent instead"
    done
  fi
done

# 5. Large component files (>300 lines)
find "$DIR" \
  \( -name "*.tsx" -o -name "*.jsx" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -name "*.test.*" \
  -not -name "*.spec.*" | while IFS= read -r file; do
  lines=$(wc -l < "$file")
  if [ "$lines" -gt 300 ]; then
    echo "$file:1 — [WARN] Component file has $lines lines (>300) → Decompose into smaller components"
  fi
done

# 6. Missing keyExtractor in FlatList / FlashList / SectionList
grep -rln $EXT '<FlatList\|<FlashList\|<SectionList' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q 'keyExtractor' "$file"; then
    grep -n '<FlatList\|<FlashList\|<SectionList' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [WARN] List without keyExtractor → Add keyExtractor={item => item.id}"
    done
  fi
done

# 7. Anonymous functions passed to React.memo / useMemo / useCallback as comparator
grep -rn $EXT 'React\.memo(\s*function\|React\.memo((\s*)(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [INFO] Anonymous function in React.memo → Name the function for better DevTools profiling"
done

# 8. setState inside a loop (while/for)
grep -rn $EXT 'for\s*(.*)\s*{' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # Check nearby lines for setState
  context=$(sed -n "$((lineno)),$((lineno + 10))p" "$file" 2>/dev/null)
  if echo "$context" | grep -q 'setState\|dispatch\|set[A-Z]'; then
    echo "$file:$lineno — [WARN] Possible setState/dispatch inside loop → Batch updates outside the loop"
  fi
done

# 9. useEffect with no dependency array (runs on every render)
grep -rn $EXT 'useEffect(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # Read next ~10 lines to look for dependency array
  context=$(sed -n "$((lineno)),$((lineno + 10))p" "$file" 2>/dev/null)
  if ! echo "$context" | grep -q '\[\])\|,\s*\['; then
    echo "$file:$lineno — [INFO] useEffect may be missing dependency array → Runs on every render if [] omitted"
  fi
done

echo ""
echo "Scan complete."

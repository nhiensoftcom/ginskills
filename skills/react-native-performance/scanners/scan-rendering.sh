#!/bin/bash
# Rendering Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Rendering Performance Scanner"
echo "================================"

# Inline arrow functions in JSX event handlers
echo ""
echo "--- Inline Functions in JSX Props ---"
grep -rn --include="*.tsx" --include="*.jsx" 'on[A-Z][a-zA-Z]*={(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      rest=$(echo "$line" | cut -d: -f3-)
      echo "$file_loc — [WARN] Inline arrow function in JSX prop → Extract to useCallback"
      ISSUES=$((ISSUES + 1))
    done

# Inline style objects
echo ""
echo "--- Inline Style Objects ---"
grep -rn --include="*.tsx" --include="*.jsx" --include="*.ts" --include="*.js" 'style={{' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v 'StyleSheet' | head -30 \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Inline style object → Move to StyleSheet.create()"
      ISSUES=$((ISSUES + 1))
    done

# key={index} or key={i} or key={idx}
echo ""
echo "--- Index as List Key ---"
grep -rn --include="*.tsx" --include="*.jsx" 'key={index}\|key={i}\b\|key={idx}' "$DIR" 2>/dev/null \
  | grep -v node_modules \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Using index as key causes O(n) re-renders → Use stable unique ID (item.id)"
      ISSUES=$((ISSUES + 1))
    done

# FlatList/SectionList inside ScrollView
echo ""
echo "--- Virtualized List Inside ScrollView ---"
grep -rln --include="*.tsx" --include="*.jsx" 'FlatList\|SectionList\|FlashList' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' \
  | while IFS= read -r file; do
      if grep -q 'ScrollView' "$file"; then
        grep -n '<FlatList\|<SectionList\|<FlashList' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] FlatList/SectionList inside ScrollView → Use ListHeaderComponent/ListFooterComponent instead"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# Large component files (>300 lines)
echo ""
echo "--- Large Component Files ---"
find "$DIR" \( -name "*.tsx" -o -name "*.jsx" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/__tests__/*" \
  -not -name "*.test.*" \
  -not -name "*.spec.*" 2>/dev/null \
  | while IFS= read -r file; do
      lines=$(wc -l < "$file" | tr -d ' ')
      if [ "$lines" -gt 300 ]; then
        echo "$file:1 — [WARN] File has $lines lines (>300) → Decompose into smaller components"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Missing keyExtractor in FlatList/FlashList/SectionList
echo ""
echo "--- List Missing keyExtractor ---"
grep -rln --include="*.tsx" --include="*.jsx" '<FlatList\|<FlashList\|<SectionList' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' \
  | while IFS= read -r file; do
      if ! grep -q 'keyExtractor' "$file"; then
        grep -n '<FlatList\|<FlashList\|<SectionList' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [WARN] List without keyExtractor → Add keyExtractor={item => item.id}"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# useEffect with no dependency array
echo ""
echo "--- useEffect Without Dependency Array ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'useEffect(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 10))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '\[\])\|,\s*\['; then
        echo "$file:$lineno — [INFO] useEffect may be missing dependency array → Runs on every render if [] omitted"
        ISSUES=$((ISSUES + 1))
      fi
    done

# setState inside a for loop
echo ""
echo "--- setState Inside Loop ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'for\s*(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 10))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'setState\|dispatch\|set[A-Z]'; then
        echo "$file:$lineno — [WARN] Possible setState/dispatch inside loop → Batch updates outside the loop"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Component definition inside render function
echo ""
echo "--- Component Definition Inside Render Function ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '^\s*function [A-Z][a-zA-Z]*(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      prev_context=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null | grep -c 'function [a-zA-Z]*\|const [A-Z][a-zA-Z]* = ' 2>/dev/null || echo 0)
      if [ "$prev_context" -gt 0 ]; then
        open_braces=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null | tr -cd '{' | wc -c | tr -d ' ')
        close_braces=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null | tr -cd '}' | wc -c | tr -d ' ')
        depth=$((open_braces - close_braces))
        if [ "$depth" -gt 1 ]; then
          echo "$file:$lineno — [ERROR] Component defined inside another function/component → Move to module scope; inner component definitions recreate on every parent render"
          ISSUES=$((ISSUES + 1))
        fi
      fi
    done

# Spreading props {...props} in JSX
echo ""
echo "--- Prop Spreading in JSX ---"
grep -rn --include="*.tsx" --include="*.jsx" \
  '{\.\.\.[a-zA-Z]*[Pp]rops}' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Spreading props in JSX ({...props}) → Passes unknown props to DOM/native elements causing extra re-renders; destructure only what you need"
      ISSUES=$((ISSUES + 1))
    done

# useMemo/useCallback with empty dependency array (often unnecessary)
echo ""
echo "--- useMemo/useCallback With Empty Deps (Possibly Unnecessary) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useMemo(\|useCallback(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q ',\s*\[\]\s*)'; then
        echo "$file:$lineno — [INFO] useMemo/useCallback with empty deps [] → Empty deps means computed once; if the value truly never changes, move it outside the component"
        ISSUES=$((ISSUES + 1))
      fi
    done

# .filter().map() chain without useMemo
echo ""
echo "--- .filter().map() Chain Without useMemo ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\.filter(.*)\.\(map\|flatMap\)\|\.filter(.*\n.*)\.\(map\|flatMap\)' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 5 ? lineno - 5 : 1)),$((lineno + 2))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'useMemo\|useCallback'; then
        echo "$file:$lineno — [WARN] .filter().map() chain without useMemo → Creates new array on every render; wrap in useMemo with the source array as dependency"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "Rendering scan complete."

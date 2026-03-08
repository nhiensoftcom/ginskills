#!/bin/bash
# TypeScript Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "TypeScript Performance Scanner"
echo "================================"

# Union types with 10+ variants in a single type
echo ""
echo "--- Large Union Types (10+ Variants) ---"
grep -rn --include="*.tsx" --include="*.ts" \
  'type [A-Za-z].*=' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      matched_line=$(echo "$line" | cut -d: -f3-)
      # Check if this is a single-line union (has | on the same line as the type declaration)
      # or a multi-line union (declaration line ends with = and values start on next lines)
      if echo "$matched_line" | grep -q '|'; then
        # Single-line union: count only pipes on the matched line itself
        pipe_count=$(echo "$matched_line" | grep -o '|' | wc -l | tr -d ' ')
      else
        # Multi-line union: declaration ends with '=', values are on subsequent lines prefixed with '|'
        # Read subsequent lines until a line that does NOT start with optional whitespace + '|'
        pipe_count=$(awk "NR > ${lineno} { if (/^[[:space:]]*\|/) { count++ } else { exit } } END { print count+0 }" "$file" 2>/dev/null)
      fi
      if [ "$pipe_count" -ge 10 ]; then
        echo "$file:$lineno — [WARN] Union type with $((pipe_count + 1))+ variants → Large unions slow down the TypeScript language server and type-checking; consider a discriminated union with a kind field or enum"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Deeply nested generic types (3+ levels)
echo ""
echo "--- Deeply Nested Generic Types (3+ Levels) ---"
grep -rn --include="*.tsx" --include="*.ts" \
  '[A-Za-z]\+<[^>]*<[^>]*<[^>]*>' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '\/\/' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Deeply nested generic type (3+ levels) → Complex generics increase type-checking time; extract intermediate types with type aliases to simplify"
      ISSUES=$((ISSUES + 1))
    done

# Interface with 50+ properties
echo ""
echo "--- Interface With 50+ Properties ---"
grep -rn --include="*.tsx" --include="*.ts" \
  '^\s*interface [A-Za-z]' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      # Count properties until closing brace
      prop_count=$(sed -n "${lineno},$((lineno + 200))p" "$file" 2>/dev/null \
        | awk '/^\s*\}/{exit} /^\s*[a-zA-Z_$][a-zA-Z0-9_$?]*\s*(\??\s*:|\()/{ count++ } END{ print count }')
      if [ -n "$prop_count" ] && [ "$prop_count" -ge 50 ]; then
        echo "$file:$lineno — [WARN] Interface with $prop_count properties → Very large interfaces slow type-checking; split into focused interfaces using intersection types (&) or extends"
        ISSUES=$((ISSUES + 1))
      fi
    done

# `as any` type assertions
echo ""
echo "--- 'as any' Type Assertions ---"
grep -rn --include="*.tsx" --include="*.ts" \
  '\bas any\b' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '\/\/.*as any' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] 'as any' type assertion → Bypasses type checking and hides real type errors; use a proper type, unknown + type guard, or a more specific cast"
      ISSUES=$((ISSUES + 1))
    done

# Missing return type annotations on exported functions
echo ""
echo "--- Exported Function Without Return Type Annotation ---"
grep -rn --include="*.tsx" --include="*.ts" \
  '^export\s\+\(async\s\+\)\?function [a-zA-Z]' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 3))p" "$file" 2>/dev/null)
      # Check for return type annotation (colon after closing paren of params)
      if ! echo "$context" | grep -qE '\)\s*:\s*[A-Za-z<\[]'; then
        echo "$file:$lineno — [INFO] Exported function without explicit return type → Missing return type forces TypeScript to infer it on every call site; add an explicit return type for faster type-checking and better documentation"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "TypeScript performance scan complete."

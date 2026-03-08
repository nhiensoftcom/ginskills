#!/bin/bash
# State & Network Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "State & Network Performance Scanner"
echo "================================"

# Context Provider with inline value object (re-creates on every render)
echo ""
echo "--- Context Provider With Inline Value Object ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\.Provider value=' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      grep -n '\.Provider value=' "$file" | while IFS= read -r match; do
        lineno=$(echo "$match" | cut -d: -f1)
        context_line=$(sed -n "${lineno}p" "$file" 2>/dev/null)
        if echo "$context_line" | grep -q 'value={{'; then
          echo "$file:$lineno — [ERROR] Context Provider with inline value object → Memoize with useMemo to prevent all consumers re-rendering on every parent render"
          ISSUES=$((ISSUES + 1))
        fi
      done
    done

# Single Context with multiple state pieces (should split)
echo ""
echo "--- Single Context With Multiple State Pieces ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'createContext\|useContext' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useState\|useReducer' "$file" && grep -q 'createContext' "$file"; then
        state_count=$(grep -c 'useState\|useReducer' "$file" 2>/dev/null || echo 0)
        context_count=$(grep -c 'createContext' "$file" 2>/dev/null || echo 0)
        if [ "$state_count" -gt 2 ] && [ "$context_count" -eq 1 ]; then
          grep -n 'createContext' "$file" | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [WARN] Single Context with multiple state pieces → Split into separate contexts (StateContext + DispatchContext) to minimize consumer re-renders"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Zustand store subscribed without selector
echo ""
echo "--- Zustand Store Without Selector ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useStore()\|use[A-Z][a-zA-Z]*Store()' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Zustand store subscribed without selector → Pass a selector: useStore(state => state.field) to avoid re-renders on unrelated state changes"
      ISSUES=$((ISSUES + 1))
    done

# Sequential await chains that could be parallelized
echo ""
echo "--- Sequential await Chains (Use Promise.all) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'await ' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      next_line=$(sed -n "$((lineno + 1))p" "$file" 2>/dev/null)
      next_next_line=$(sed -n "$((lineno + 2))p" "$file" 2>/dev/null)
      if echo "$next_line" | grep -q 'await ' && echo "$next_next_line" | grep -q 'await \|const\|let'; then
        curr_var=$(sed -n "${lineno}p" "$file" | grep -oE 'const [a-zA-Z]+|let [a-zA-Z]+' | head -1 | awk '{print $2}')
        if [ -n "$curr_var" ] && ! echo "$next_line" | grep -q "$curr_var"; then
          echo "$file:$lineno — [WARN] Sequential await chain → Use Promise.all([op1(), op2()]) to run independent async operations in parallel"
          ISSUES=$((ISSUES + 1))
        fi
      fi
    done

# setInterval used for API polling
echo ""
echo "--- setInterval for API Polling ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'setInterval(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 5))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'fetch(\|axios\.\|api\.\|refetch\|load\|getData'; then
        echo "$file:$lineno — [WARN] setInterval used for API polling → Use React Query's refetchInterval or WebSocket for real-time data"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Raw fetch/axios without React Query (multiple calls per file)
echo ""
echo "--- Raw fetch/axios Without React Query ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'fetch(\|axios\.' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'useQuery\|useMutation\|useSWR\|useInfiniteQuery\|@tanstack' "$file"; then
        fetch_count=$(grep -c 'fetch(\|axios\.' "$file" 2>/dev/null || echo 0)
        if [ "$fetch_count" -gt 2 ]; then
          grep -n 'fetch(\|axios\.' "$file" | head -3 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [WARN] Raw fetch/axios without React Query ($fetch_count calls in file) → Add @tanstack/react-query for caching, deduplication, and background refresh"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# useSelector with inline object selector (new reference each render)
echo ""
echo "--- useSelector With Inline Object Selector ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useSelector(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      if echo "$line" | grep -qE 'useSelector\(\s*state\s*=>\s*\{'; then
        file_loc=$(echo "$line" | cut -d: -f1,2)
        echo "$file_loc — [WARN] useSelector with inline object selector → Inline selectors return new references; use reselect createSelector or select a primitive"
        ISSUES=$((ISSUES + 1))
      fi
    done

# useState with large inline object (should use useReducer)
echo ""
echo "--- useState With Large Object (Use useReducer) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useState({' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 10))p" "$file" 2>/dev/null)
      field_count=$(echo "$context" | grep -c '^\s*[a-zA-Z]\+:' 2>/dev/null || echo 0)
      if [ "$field_count" -gt 4 ]; then
        echo "$file:$lineno — [WARN] useState with large object ($field_count+ fields) → Use useReducer for complex state or split into multiple useState calls"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Direct state mutation
echo ""
echo "--- Direct State Mutation ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\bstate\.[a-zA-Z]* =' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '\/\/\|const state\|let state\|var state\|initialState\|useState\|//\s*state' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Possible direct state mutation → Use setState/dispatch with new object; direct mutation won't trigger re-render"
      ISSUES=$((ISSUES + 1))
    done

# Missing loading/error states for async operations
echo ""
echo "--- Missing Loading/Error States ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'async\s\|await\s' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useEffect\|fetch(\|axios\.' "$file"; then
        if ! grep -q 'isLoading\|loading\|isPending\|isFetching\|isError\|error' "$file"; then
          grep -n 'useEffect(' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [INFO] Async operations without loading/error state tracking → Track loading and error states for better UX and to prevent race conditions"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Multiple sequential setState calls (should batch)
echo ""
echo "--- Multiple Sequential setState Calls ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'set[A-Z][a-zA-Z]*(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      next_line=$(sed -n "$((lineno + 1))p" "$file" 2>/dev/null)
      curr_line=$(sed -n "${lineno}p" "$file" 2>/dev/null)
      if echo "$next_line" | grep -qE '^\s+set[A-Z][a-zA-Z]*(' && echo "$curr_line" | grep -qE '^\s+set[A-Z][a-zA-Z]*('; then
        echo "$file:$lineno — [WARN] Multiple sequential setState calls → React 18 auto-batches inside event handlers, but sequential calls in async contexts may cause multiple renders; use useReducer or a single state object"
        ISSUES=$((ISSUES + 1))
      fi
    done

# useSelector with new object/array creation (creates new ref each render)
echo ""
echo "--- useSelector Creating New Object/Array Reference ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useSelector(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 3))p" "$file" 2>/dev/null)
      if echo "$context" | grep -qE 'useSelector\(.*=>\s*(\[|\{|\.map\(|\.filter\(|\.slice\()'; then
        echo "$file:$lineno — [ERROR] useSelector returning new object/array literal or derived array → Creates a new reference every render causing re-subscribe; use reselect createSelector for memoized derived data"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Missing error boundary around async operations
echo ""
echo "--- Async Screen Without Error Boundary ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useNavigation\|useRoute' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useQuery\|useMutation\|fetch(\|axios\.' "$file"; then
        if ! grep -q 'ErrorBoundary\|error-boundary\|errorBoundary' "$file"; then
          grep -n 'useQuery\|useMutation' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [WARN] Screen with async operations but no ErrorBoundary → Wrap async screens with an ErrorBoundary to catch render-phase errors from failed queries"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Using new Date() or Math.random() in selectors
echo ""
echo "--- new Date() or Math.random() in Selector/Render ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'new Date()\|Math\.random()' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v 'useMemo\|useCallback\|useRef\|const.*=.*new Date\|defaultValue\|initialState\|useState(' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 3 ? lineno - 3 : 1)),$((lineno + 1))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'useSelector\|selector\|createSelector\|return\s'; then
        echo "$file:$lineno — [ERROR] new Date() or Math.random() in selector/render → Non-deterministic values in selectors break memoization; compute outside the selector or use a stable timestamp from state"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "State & network scan complete."

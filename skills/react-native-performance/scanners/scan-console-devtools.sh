#!/bin/bash
# Console & DevTools Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Console & DevTools Scanner"
echo "================================"

# console.log without __DEV__ guard
echo ""
echo "--- console.log Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'console\.log(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '__DEV__' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      # Check a 10-line context window above the call for any __DEV__ reference,
      # catching both direct `if (__DEV__)` guards and indirect patterns like
      # `const DEBUG = __DEV__` followed by `if (!DEBUG) return`.
      # Also scan the whole file above for a module-level `__DEV__` variable assignment
      # (e.g. `const DEBUG_ENABLED = __DEV__`) that an early-return guard may reference.
      context=$(sed -n "$((lineno > 10 ? lineno - 10 : 1)),$((lineno - 1))p" "$file" 2>/dev/null)
      file_context=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '__DEV__\|if.*DEV' && \
         ! echo "$file_context" | grep -q '= __DEV__'; then
        echo "$file:$lineno — [WARN] console.log without __DEV__ guard → Wrap with if (__DEV__) or use babel-plugin-transform-remove-console"
        ISSUES=$((ISSUES + 1))
      fi
    done

# console.warn without __DEV__ guard
echo ""
echo "--- console.warn Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'console\.warn(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '__DEV__' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      # Check a 10-line context window above the call for any __DEV__ reference.
      # Also scan the whole file above for a module-level `= __DEV__` variable assignment
      # that an early-return guard may reference indirectly.
      context=$(sed -n "$((lineno > 10 ? lineno - 10 : 1)),$((lineno - 1))p" "$file" 2>/dev/null)
      file_context=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '__DEV__\|if.*DEV' && \
         ! echo "$file_context" | grep -q '= __DEV__'; then
        echo "$file:$lineno — [WARN] console.warn without __DEV__ guard → Wrap with if (__DEV__) or suppress in production logger"
        ISSUES=$((ISSUES + 1))
      fi
    done

# console.error without __DEV__ guard (informational — may be intentional for crash reporting)
echo ""
echo "--- console.error Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'console\.error(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '__DEV__\|Sentry\|crashlytics\|bugsnag' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] console.error in production code → Use a crash reporting SDK (Sentry/Crashlytics) instead of console.error"
      ISSUES=$((ISSUES + 1))
    done

# console.info / console.debug without __DEV__ guard
echo ""
echo "--- console.info / console.debug Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'console\.info(\|console\.debug(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] console.info/debug in production code → Remove or guard with if (__DEV__)"
      ISSUES=$((ISSUES + 1))
    done

# debugger statements
echo ""
echo "--- debugger Statements ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\bdebugger\b' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] debugger statement left in code → Remove immediately; pauses JS execution in production"
      ISSUES=$((ISSUES + 1))
    done

# Flipper imports
echo ""
echo "--- Flipper Imports ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-native-flipper'\|require('react-native-flipper')\|from \"react-native-flipper\"\|addPlugin\|FlipperPlugin" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '__DEV__\|debug\|Debug' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Flipper import outside __DEV__ guard → Wrap Flipper initialization in if (__DEV__) to exclude from production bundle"
      ISSUES=$((ISSUES + 1))
    done

# TODO comments
echo ""
echo "--- TODO Comments ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'TODO\|todo:' "$DIR" 2>/dev/null \
  | grep -v node_modules \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] TODO comment → Track as a ticket or resolve before release"
      ISSUES=$((ISSUES + 1))
    done

# FIXME comments
echo ""
echo "--- FIXME Comments ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'FIXME\|fixme:' "$DIR" 2>/dev/null \
  | grep -v node_modules \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] FIXME comment → Known issue that must be resolved; do not ship to production"
      ISSUES=$((ISSUES + 1))
    done

# HACK comments
echo ""
echo "--- HACK Comments ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\bHACK\b\|hack:' "$DIR" 2>/dev/null \
  | grep -v node_modules \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] HACK comment → Temporary workaround detected; document the issue and plan proper fix"
      ISSUES=$((ISSUES + 1))
    done

# Production-critical logic inside __DEV__ blocks (anti-pattern)
echo ""
echo "--- Production Logic Inside __DEV__ Block ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'if\s*(__DEV__)' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 10))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'navigate\|dispatch\|setState\|fetch(\|api\.'; then
        echo "$file:$lineno — [WARN] Production-critical logic inside __DEV__ block → State changes/navigation inside __DEV__ blocks will not run in production; this may be a bug"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Hardcoded localhost / dev URLs
echo ""
echo "--- Hardcoded localhost / Dev URLs ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'localhost\|127\.0\.0\.1\|192\.168\.' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '//.*localhost\|\.env' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      # Skip lines that themselves reference __DEV__ (e.g. `if (!__DEV__ || ...localhost...)`)
      # Also skip lines that are inside a __DEV__-guarded block by scanning the entire
      # preceding file content up to this line (handles early-return guards at any distance).
      match_line=$(echo "$line" | cut -d: -f3-)
      if echo "$match_line" | grep -q '__DEV__'; then
        continue
      fi
      context=$(sed -n "$((lineno > 30 ? lineno - 30 : 1)),$((lineno - 1))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q '__DEV__'; then
        continue
      fi
      echo "$file:$lineno — [ERROR] Hardcoded local/dev URL → Use environment variables (process.env / Config) for API base URLs"
      ISSUES=$((ISSUES + 1))
    done

# React Profiler without __DEV__ guard
echo ""
echo "--- React Profiler Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'ReactDevTools\|enableProfiling\|<Profiler ' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '__DEV__' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] React Profiler/DevTools without __DEV__ guard → Profiling adds overhead; wrap with if (__DEV__) or remove from production builds"
      ISSUES=$((ISSUES + 1))
    done

# Redux DevTools middleware in production
echo ""
echo "--- Redux DevTools Middleware Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'composeWithDevTools\|redux-devtools-extension\|DevTools\.instrument\|reduxDevtools' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 3 ? lineno - 3 : 1)),$((lineno + 3))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '__DEV__'; then
        echo "$file:$lineno — [ERROR] Redux DevTools middleware without __DEV__ guard → DevTools add significant overhead; wrap with if (__DEV__) to exclude from production builds"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Performance.mark/measure without __DEV__ guard
echo ""
echo "--- performance.mark/measure Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'performance\.mark(\|performance\.measure(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 3 ? lineno - 3 : 1)),$((lineno + 1))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '__DEV__'; then
        echo "$file:$lineno — [WARN] performance.mark/measure without __DEV__ guard → Performance timing APIs add overhead in production; wrap with if (__DEV__)"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Sentry debug mode enabled in production
echo ""
echo "--- Sentry debug: true Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Sentry\.init(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 10))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'debug:\s*true'; then
        if ! echo "$context" | grep -q '__DEV__'; then
          echo "$file:$lineno — [ERROR] Sentry initialized with debug: true without __DEV__ guard → debug mode logs all events to console and slows production; use debug: __DEV__"
          ISSUES=$((ISSUES + 1))
        fi
      fi
    done

# react-native-flipper import without __DEV__ guard
echo ""
echo "--- react-native-flipper Import Without __DEV__ Guard ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-native-flipper'\|require('react-native-flipper')\|from \"react-native-flipper\"\|require(\"react-native-flipper\")" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 5 ? lineno - 5 : 1)),$((lineno + 2))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q '__DEV__'; then
        echo "$file:$lineno — [ERROR] react-native-flipper imported without __DEV__ guard → Flipper is a debug tool; guard with if (__DEV__) or use dynamic require to exclude from production bundle"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "Console & DevTools scan complete."

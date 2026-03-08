#!/bin/bash
# Bundle Size Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Bundle Size Scanner"
echo "================================"

# Full lodash import (not tree-shakeable)
echo ""
echo "--- Full lodash Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "import _ from 'lodash'\|import _ from \"lodash\"\|import { .* } from 'lodash'\|import { .* } from \"lodash\"\|from 'lodash'" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Full lodash import (~70KB) → Use 'lodash/get', 'lodash/merge' etc. or native JS equivalents"
      ISSUES=$((ISSUES + 1))
    done

# moment.js import (~300KB)
echo ""
echo "--- moment.js Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "import moment from 'moment'\|import moment from \"moment\"\|require('moment')\|require(\"moment\")" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] moment.js import (~300KB) → Replace with date-fns (tree-shakeable) or dayjs (~2KB)"
      ISSUES=$((ISSUES + 1))
    done

# Full firebase import (non-modular)
echo ""
echo "--- Full firebase Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "import firebase from 'firebase'\|import firebase from \"firebase\"\|require('firebase')\|require(\"firebase\")" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Full firebase import → Use modular imports: import { getAuth } from 'firebase/auth'"
      ISSUES=$((ISSUES + 1))
    done

# axios import
echo ""
echo "--- axios Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "import axios from 'axios'\|import axios from \"axios\"\|import \* as axios from 'axios'" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] axios import (~13KB) → Consider native fetch() or a lightweight wrapper like ky"
      ISSUES=$((ISSUES + 1))
    done

# Full icon library imports
echo ""
echo "--- Full Icon Library Imports ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from '@expo/vector-icons'\$\|from \"@expo/vector-icons\"\$\|import \* as.*Icons" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Wildcard icon import → Import only the specific icon set: from '@expo/vector-icons/Ionicons'"
      ISSUES=$((ISSUES + 1))
    done

# react-native-vector-icons barrel imports
echo ""
echo "--- react-native-vector-icons Barrel Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-native-vector-icons'\$\|from \"react-native-vector-icons\"\$" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Full vector-icons import → Import specific set: from 'react-native-vector-icons/Ionicons'"
      ISSUES=$((ISSUES + 1))
    done

# Barrel file detection (index files that are mostly re-exports)
echo ""
echo "--- Barrel Files Blocking Tree-shaking ---"
find "$DIR" \( -name "index.ts" -o -name "index.tsx" -o -name "index.js" -o -name "index.jsx" \) \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      total=$(wc -l < "$file" | tr -d ' ')
      exports=$(grep -c '^export \({\|default\|\*\|type\)' "$file" 2>/dev/null || echo 0)
      if [ "$total" -gt 0 ] && [ "$exports" -gt 5 ]; then
        ratio=$((exports * 100 / total))
        if [ "$ratio" -gt 70 ]; then
          echo "$file:1 — [WARN] Barrel file with $exports re-exports (${ratio}% of file) → Barrel files block tree-shaking; import directly from source files"
          ISSUES=$((ISSUES + 1))
        fi
      fi
    done

# Missing babel-plugin-transform-remove-console
echo ""
echo "--- babel.config Missing transform-remove-console ---"
find "$DIR" -maxdepth 4 \
  \( -name "babel.config.js" -o -name "babel.config.ts" -o -name ".babelrc" -o -name ".babelrc.js" \) \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      if ! grep -q 'transform-remove-console\|remove-console' "$file"; then
        echo "$file:1 — [WARN] babel.config missing transform-remove-console → Add to plugins: ['transform-remove-console', { exclude: ['error'] }]"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Node built-ins (crypto/buffer require large shims)
echo ""
echo "--- Node Built-in Imports ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'crypto'\|from \"crypto\"\|require('crypto')\|from 'buffer'\|from \"buffer\"\|require('buffer')" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Node built-in import (crypto/buffer) → These require large shims in RN; use platform-native alternatives"
      ISSUES=$((ISSUES + 1))
    done

# date-fns full import
echo ""
echo "--- Full date-fns Import ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "import \* as dateFns from 'date-fns'\|import dateFns from 'date-fns'" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Full date-fns import → Use named imports: import { format, parseISO } from 'date-fns'"
      ISSUES=$((ISSUES + 1))
    done

# Legacy react-query package
echo ""
echo "--- Legacy react-query Package ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-query'\|from \"react-query\"" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] Using legacy react-query package → Migrate to @tanstack/react-query v5 for better tree-shaking"
      ISSUES=$((ISSUES + 1))
    done

# import * as for utility libraries (prevents tree shaking)
echo ""
echo "--- Wildcard import * as (Prevents Tree-shaking) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'import \* as ' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v "from 'react'\|from \"react\"\|from 'react-native'\|from \"react-native\"" \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Wildcard namespace import (import * as) → Prevents tree-shaking; use named imports to allow bundler to eliminate unused exports"
      ISSUES=$((ISSUES + 1))
    done

# Polyfill imports (babel-polyfill, core-js full)
echo ""
echo "--- Polyfill Imports ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from '@babel/polyfill'\|from \"@babel/polyfill\"\|require('@babel/polyfill')\|require(\"@babel/polyfill\")\|from 'babel-polyfill'\|from \"babel-polyfill\"\|from 'core-js'\|from \"core-js\"\|require('core-js')\|require(\"core-js\")" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] Full polyfill import (babel-polyfill/core-js) adds hundreds of KB → Hermes covers modern JS; remove polyfills or use targeted core-js/stable imports"
      ISSUES=$((ISSUES + 1))
    done

# Large JSON imports (i18n translation files loaded upfront)
echo ""
echo "--- Large JSON Import (i18n/translation files) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "require('.*\.\(json\)')\|require(\".*\.\(json\)\")\|from '.*\(translations\|i18n\|locales\|locale\).*\.json'\|from \".*\(translations\|i18n\|locales\|locale\).*\.json\"" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Static JSON translation file imported upfront → Use dynamic import() to load locale files on demand; only load the active locale at startup"
      ISSUES=$((ISSUES + 1))
    done

# Unused @react-native-community packages
echo ""
echo "--- @react-native-community Package Imports ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from '@react-native-community/" "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      pkg=$(echo "$line" | grep -oE "@react-native-community/[a-zA-Z0-9_-]+" | head -1)
      echo "$file_loc — [INFO] @react-native-community package ($pkg) → Verify this package is still actively maintained; many have been superseded by React Native core or better alternatives"
      ISSUES=$((ISSUES + 1))
    done

echo ""
echo "Bundle size scan complete."

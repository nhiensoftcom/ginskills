#!/bin/bash
# React Native Bundle Size Scanner
DIR="${1:-.}"
EXT="--include=*.tsx --include=*.ts --include=*.jsx --include=*.js"

echo "Scanning for bundle size issues in $DIR..."
echo "=================================================="

# 1. Full lodash import (not tree-shakeable in most bundlers)
grep -rn $EXT "import _ from 'lodash'\|import _ from \"lodash\"\|import { .* } from 'lodash'\|import { .* } from \"lodash\"" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [ERROR] Full lodash import (~70KB) → Use 'lodash/get', 'lodash/merge' etc. or native JS equivalents"
done

# 2. moment.js import (massive, ~300KB)
grep -rn $EXT "import moment from 'moment'\|import moment from \"moment\"\|require('moment')\|require(\"moment\")" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [ERROR] moment.js import (~300KB) → Replace with date-fns (tree-shakeable) or dayjs (~2KB)"
done

# 3. Full firebase import (not modular)
grep -rn $EXT "import firebase from 'firebase'\|import firebase from \"firebase\"\|require('firebase')\|require(\"firebase\")" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [ERROR] Full firebase import → Use modular imports: import { getAuth } from 'firebase/auth'"
done

# 4. axios import (when fetch is available in RN)
grep -rn $EXT "import axios from 'axios'\|import axios from \"axios\"\|import \* as axios from 'axios'" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] axios import (~13KB) → Consider native fetch() or a lightweight wrapper like ky"
done

# 5. Full icon library imports (e.g., react-native-vector-icons full set, @expo/vector-icons full)
grep -rn $EXT "import \* as.*Icons\|from '@expo/vector-icons'$\|from \"@expo/vector-icons\"$" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] Wildcard icon import → Import only the specific icon set: from '@expo/vector-icons/Ionicons'"
done

# 6. react-native-vector-icons barrel imports
grep -rn $EXT "from 'react-native-vector-icons'$\|from \"react-native-vector-icons\"$" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] Full vector-icons import → Import specific set: from 'react-native-vector-icons/Ionicons'"
done

# 7. Barrel file detection (index.ts that is mostly re-exports)
find "$DIR" \
  \( -name "index.ts" -o -name "index.tsx" -o -name "index.js" -o -name "index.jsx" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" | while IFS= read -r file; do
  total=$(wc -l < "$file")
  exports=$(grep -c '^export \({\|default\|\*\|type\)' "$file" 2>/dev/null || echo 0)
  if [ "$total" -gt 0 ] && [ "$exports" -gt 5 ]; then
    ratio=$((exports * 100 / total))
    if [ "$ratio" -gt 70 ]; then
      echo "$file:1 — [WARN] Barrel file with $exports re-exports (${ratio}% of file) → Barrel files block tree-shaking; import directly from source files"
    fi
  fi
done

# 8. Missing babel-plugin-transform-remove-console check
find "$DIR" -maxdepth 3 \
  \( -name "babel.config.js" -o -name "babel.config.ts" -o -name ".babelrc" -o -name ".babelrc.js" \) \
  -not -path "*/node_modules/*" | while IFS= read -r file; do
  if ! grep -q 'transform-remove-console\|remove-console' "$file"; then
    echo "$file:1 — [WARN] babel.config missing transform-remove-console → Add to plugins for production: ['transform-remove-console', { exclude: ['error'] }]"
  fi
done

# 9. crypto / buffer / stream (Node built-ins shim = bloat)
grep -rn $EXT "from 'crypto'\|from \"crypto\"\|require('crypto')\|from 'buffer'\|from \"buffer\"\|require('buffer')" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] Node built-in import (crypto/buffer) → These require large shims in RN; use platform-native alternatives"
done

# 10. Large JSON imports
grep -rn $EXT "from '.*\.json'\|require('.*\.json')" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # Extract the JSON path
  json_path=$(echo "$line" | grep -oE "['\"](.*\.json)['\"]" | tr -d "'\"")
  if [ -n "$json_path" ]; then
    full_path="$DIR/$json_path"
    if [ -f "$full_path" ]; then
      size=$(wc -c < "$full_path" 2>/dev/null || echo 0)
      if [ "$size" -gt 50000 ]; then
        echo "$file:$lineno — [WARN] Large JSON import ($(( size / 1024 ))KB) → Lazy load or paginate this data"
      fi
    fi
  fi
done

# 11. date-fns full import (should use named imports)
grep -rn $EXT "import \* as dateFns from 'date-fns'\|import dateFns from 'date-fns'" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [WARN] Full date-fns import → Use named imports: import { format, parseISO } from 'date-fns'"
done

# 12. react-query/react without specifying @tanstack/react-query (older, heavier)
grep -rn $EXT "from 'react-query'\|from \"react-query\"" "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  echo "$line — [INFO] Using legacy react-query package → Migrate to @tanstack/react-query v5 for better tree-shaking"
done

echo ""
echo "Scan complete."

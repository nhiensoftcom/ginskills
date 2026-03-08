#!/bin/bash
# Unused Assets Scanner
# Detects static files (images, fonts, JSON, SVG components) that exist in the codebase
# but are never referenced or imported anywhere in source files. Unreferenced assets
# bloat the repository and — for bundled assets — waste app install size.
#
# Checks:
#   1. Unused image files (.png .jpg .jpeg .gif .webp .svg)
#   2. Unused font files (.ttf .otf .woff .woff2)
#   3. Unused JSON data files (excluding well-known config files)
#   4. Unused SVG component files in icon/asset directories
#   5. Duplicate assets — same base name, different extensions
#   6. Any unreferenced file > 100 KB is escalated to ERROR

DIR="${1:-./src}"
TMPFILE=$(mktemp)

echo "Unused Assets Scanner"
echo "================================"

# ---------------------------------------------------------------------------
# Helper: strip @2x / @3x / @3.5x density suffixes and extension from a filename
# e.g. "logo@2x.png" → "logo"  |  "icon.png" → "icon"
# ---------------------------------------------------------------------------
strip_suffix() {
  # Remove known density suffixes, then the extension
  echo "$1" \
    | sed 's/@[0-9][0-9]*\(\.[0-9][0-9]*\)*x\(\.[^.]*\)$/\2/' \
    | sed 's/\.[^.]*$//'
}

# ---------------------------------------------------------------------------
# 1. Unused image files
# ---------------------------------------------------------------------------
echo ""
echo "--- Unused Image Files ---"

# Collect all source files once to avoid re-running find per asset
SRC_TMPFILE=$(mktemp)
find "$DIR" \
  \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/__tests__/*" \
  -not -name "*.test.*" \
  -not -name "*.spec.*" \
  2>/dev/null > "$SRC_TMPFILE"

# Concatenate all source content once for fast grep
SRC_CONTENT_TMPFILE=$(mktemp)
while IFS= read -r sf; do
  cat "$sf" 2>/dev/null
done < "$SRC_TMPFILE" > "$SRC_CONTENT_TMPFILE"

# Track base names already reported (to group @2x/@3x variants)
SEEN_BASES_TMPFILE=$(mktemp)

find "$DIR" \
  \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \
     -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) \
  -not -path "*/node_modules/*" \
  2>/dev/null \
  | sort \
  | while IFS= read -r asset; do
      filename=$(basename "$asset")
      base=$(strip_suffix "$filename")

      # Skip if we already reported this base name (variant grouping)
      if grep -qxF "$base" "$SEEN_BASES_TMPFILE" 2>/dev/null; then
        continue
      fi
      echo "$base" >> "$SEEN_BASES_TMPFILE"

      # Check whether the base name (or full filename) appears in any source file
      if ! grep -qF "$base" "$SRC_CONTENT_TMPFILE" 2>/dev/null; then
        size=$(wc -c < "$asset" 2>/dev/null | tr -d ' ')
        size=${size:-0}
        kb=$(( size / 1024 ))
        if [ "$size" -gt 102400 ]; then
          echo "$asset:1 — [ERROR] Unused image '${filename}' (${kb}KB) never referenced in source → Large unreferenced asset wastes bundle/install size; delete or import it"
        else
          echo "$asset:1 — [WARN] Unused image '${filename}' never referenced in source → Remove the file or add a require()/import to use it"
        fi
        echo 1 >> "$TMPFILE"
      fi
    done

rm -f "$SEEN_BASES_TMPFILE"

# ---------------------------------------------------------------------------
# 2. Unused font files
# ---------------------------------------------------------------------------
echo ""
echo "--- Unused Font Files ---"

# Also collect config files that declare fonts
FONT_CONFIG_TMPFILE=$(mktemp)
find "${DIR%/src}" \
  \( -name "react-native.config.js" -o -name "react-native.config.ts" \
     -o -name "app.json" -o -name "app.config.js" -o -name "app.config.ts" \
     -o -name "*.css" \) \
  -not -path "*/node_modules/*" \
  -maxdepth 6 \
  2>/dev/null \
  | while IFS= read -r cf; do cat "$cf" 2>/dev/null; done > "$FONT_CONFIG_TMPFILE"

find "$DIR" \
  \( -name "*.ttf" -o -name "*.otf" -o -name "*.woff" -o -name "*.woff2" \) \
  -not -path "*/node_modules/*" \
  2>/dev/null \
  | sort \
  | while IFS= read -r asset; do
      filename=$(basename "$asset")
      base="${filename%.*}"

      # Check source files and config files
      if ! grep -qF "$base" "$SRC_CONTENT_TMPFILE" 2>/dev/null \
         && ! grep -qF "$base" "$FONT_CONFIG_TMPFILE" 2>/dev/null \
         && ! grep -qF "$filename" "$SRC_CONTENT_TMPFILE" 2>/dev/null \
         && ! grep -qF "$filename" "$FONT_CONFIG_TMPFILE" 2>/dev/null; then
        size=$(wc -c < "$asset" 2>/dev/null | tr -d ' ')
        size=${size:-0}
        kb=$(( size / 1024 ))
        if [ "$size" -gt 102400 ]; then
          echo "$asset:1 — [ERROR] Unused font '${filename}' (${kb}KB) never referenced → Large unreferenced font wastes install size; remove it or register it in react-native.config.js"
        else
          echo "$asset:1 — [WARN] Unused font '${filename}' never referenced in source or config → Remove the file or register it in react-native.config.js / app.json"
        fi
        echo 1 >> "$TMPFILE"
      fi
    done

rm -f "$FONT_CONFIG_TMPFILE"

# ---------------------------------------------------------------------------
# 3. Unused JSON data files
# ---------------------------------------------------------------------------
echo ""
echo "--- Unused JSON Data Files ---"

# Well-known config/tooling filenames to always skip
SKIP_JSON="package.json|package-lock.json|tsconfig.json|tsconfig.*.json|jest.config.json|.eslintrc.json|.prettierrc.json|.babelrc.json|babel.config.json|app.json|eas.json|expo.json|firebase.json|google-services.json|GoogleService-Info.plist"

find "$DIR" \
  -name "*.json" \
  -not -path "*/node_modules/*" \
  2>/dev/null \
  | sort \
  | while IFS= read -r asset; do
      filename=$(basename "$asset")

      # Skip well-known config files
      skip=false
      for pattern in package.json package-lock.json tsconfig.json jest.config.json \
                     .eslintrc.json .prettierrc.json .babelrc.json babel.config.json \
                     app.json eas.json expo.json firebase.json google-services.json; do
        if [ "$filename" = "$pattern" ]; then
          skip=true
          break
        fi
      done
      # Also skip tsconfig.*.json variants
      if echo "$filename" | grep -qE '^tsconfig\..*\.json$'; then
        skip=true
      fi
      $skip && continue

      base="${filename%.json}"
      # Check by filename and base name
      if ! grep -qF "$filename" "$SRC_CONTENT_TMPFILE" 2>/dev/null \
         && ! grep -qF "$base" "$SRC_CONTENT_TMPFILE" 2>/dev/null; then
        size=$(wc -c < "$asset" 2>/dev/null | tr -d ' ')
        size=${size:-0}
        kb=$(( size / 1024 ))
        if [ "$size" -gt 102400 ]; then
          echo "$asset:1 — [ERROR] Unused JSON file '${filename}' (${kb}KB) never imported → Large unused data file wastes install/bundle size; delete or import it"
        else
          echo "$asset:1 — [INFO] Unused JSON file '${filename}' never imported → Remove the file or import it where needed"
        fi
        echo 1 >> "$TMPFILE"
      fi
    done

# ---------------------------------------------------------------------------
# 4. Unused SVG component files in icon/asset directories
# ---------------------------------------------------------------------------
echo ""
echo "--- Unused SVG Component Files (Icon/Asset Directories) ---"

find "$DIR" \
  \( -name "*.tsx" -o -name "*.ts" \) \
  -not -path "*/node_modules/*" \
  -not -name "*.test.*" \
  -not -name "*.spec.*" \
  2>/dev/null \
  | grep -E '/(icons?|svgs?|assets?/icons?|assets?/svgs?|assets?/images?)/' \
  | sort \
  | while IFS= read -r asset; do
      filename=$(basename "$asset")
      base="${filename%.*}"

      # Derive PascalCase component name candidates:
      # e.g. "cute-check-stamp" → "CuteCheckStamp", "ArrowRight" → "ArrowRight"
      # Remove extension, replace hyphens/underscores with spaces, title-case each word
      component=$(echo "$base" \
        | sed 's/[-_]/ /g' \
        | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}' \
        | tr -d ' ')

      # Check whether the file itself or its component name is imported elsewhere
      # Exclude the asset file itself from the search
      if ! grep -rn --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
              -l "$base\|$component" "$DIR" 2>/dev/null \
         | grep -v "$(echo "$asset" | sed 's|/|\\/|g')" \
         | grep -v node_modules \
         | grep -q .; then
        size=$(wc -c < "$asset" 2>/dev/null | tr -d ' ')
        size=${size:-0}
        kb=$(( size / 1024 ))
        if [ "$size" -gt 102400 ]; then
          echo "$asset:1 — [ERROR] Unused SVG component '${component}' (${kb}KB) in icon directory never imported → Remove unused icon component to reduce bundle size"
        else
          echo "$asset:1 — [WARN] Unused SVG component '${component}' in icon directory never imported → Remove or use the component; dead icon files add noise to the codebase"
        fi
        echo 1 >> "$TMPFILE"
      fi
    done

# ---------------------------------------------------------------------------
# 5. Duplicate assets (same base name, different extensions)
# ---------------------------------------------------------------------------
echo ""
echo "--- Duplicate Assets (Same Name, Different Extensions) ---"

DUP_TMPFILE=$(mktemp)

find "$DIR" \
  \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \
     -o -name "*.gif" -o -name "*.webp" -o -name "*.svg" \) \
  -not -path "*/node_modules/*" \
  2>/dev/null \
  | while IFS= read -r asset; do
      filename=$(basename "$asset")
      # Normalise: strip @2x/@3x suffix then extension
      base=$(strip_suffix "$filename")
      dir=$(dirname "$asset")
      echo "${dir}/${base}"
    done \
  | sort \
  | uniq -d \
  > "$DUP_TMPFILE"

while IFS= read -r dup_base; do
  # Find the actual duplicates
  matches=$(find "$(dirname "$dup_base")" -maxdepth 1 \
    \( -name "$(basename "$dup_base").*" \
       -o -name "$(basename "$dup_base")@*" \) \
    2>/dev/null | head -10 | tr '\n' ' ')
  echo "${dup_base}:1 — [INFO] Duplicate asset base name '$(basename "$dup_base")' exists with multiple extensions: ${matches}→ Consolidate to one format (prefer WebP); the unused variant wastes storage"
  echo 1 >> "$TMPFILE"
done < "$DUP_TMPFILE"

rm -f "$DUP_TMPFILE"

# ---------------------------------------------------------------------------
# Cleanup and summary
# ---------------------------------------------------------------------------
rm -f "$SRC_TMPFILE"
rm -f "$SRC_CONTENT_TMPFILE"

ISSUES=$(wc -l < "$TMPFILE" 2>/dev/null | tr -d ' ')
rm -f "$TMPFILE"

echo ""
echo "Unused assets scan complete. Total issues found: ${ISSUES:-0}"

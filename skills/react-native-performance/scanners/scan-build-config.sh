#!/bin/bash
# Build Configuration Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Build Configuration Scanner"
echo "================================"

# Hermes not enabled in android/app/build.gradle
echo ""
echo "--- Hermes Not Enabled in Android Build ---"
find "${DIR%/src}" \( -path "*/android/app/build.gradle" -o -path "*/android/app/build.gradle.kts" \) \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      if ! grep -q 'hermesEnabled.*=.*true\|hermes_enabled.*=.*true\|enableHermes.*=.*true' "$file"; then
        echo "$file:1 — [ERROR] Hermes not enabled in android/app/build.gradle → Add hermesEnabled = true in the android { defaultConfig {} } block; Hermes significantly reduces startup time and memory usage"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Missing ProGuard/R8 rules
echo ""
echo "--- Missing ProGuard/R8 Rules ---"
find "${DIR%/src}" -path "*/android/app/build.gradle" \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      if ! grep -q 'proguardFiles\|minifyEnabled\s*=\s*true' "$file"; then
        echo "$file:1 — [WARN] ProGuard/R8 not configured in android/app/build.gradle → Enable minifyEnabled = true and proguardFiles in release buildType to shrink and obfuscate the production APK"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Metro config missing inlineRequires
echo ""
echo "--- Metro Config Missing inlineRequires ---"
find "${DIR%/src}" \( -name "metro.config.js" -o -name "metro.config.ts" \) \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      if ! grep -q 'inlineRequires' "$file"; then
        echo "$file:1 — [WARN] metro.config missing inlineRequires optimization → Add transformer: { getTransformOptions: async () => ({ transform: { inlineRequires: true } }) } to defer module evaluation and improve startup time"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Missing babel-plugin-transform-remove-console in babel config
echo ""
echo "--- babel.config Missing transform-remove-console ---"
find "${DIR%/src}" \( -name "babel.config.js" -o -name "babel.config.ts" -o -name ".babelrc" -o -name ".babelrc.js" \) \
  -not -path "*/node_modules/*" -maxdepth 4 2>/dev/null \
  | while IFS= read -r file; do
      if ! grep -q 'transform-remove-console\|remove-console' "$file"; then
        echo "$file:1 — [WARN] babel.config missing transform-remove-console → Add ['transform-remove-console', { exclude: ['error'] }] to plugins to strip console calls from the production bundle"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Flipper not excluded from release builds in android/app/build.gradle
echo ""
echo "--- Flipper Not Excluded From Release Builds ---"
find "${DIR%/src}" -path "*/android/app/build.gradle" \
  -not -path "*/node_modules/*" 2>/dev/null \
  | while IFS= read -r file; do
      if grep -q 'flipper\|Flipper' "$file"; then
        if ! grep -q 'releaseImplementation.*flipper\|!enableFlipper\|flipper.*release.*false\|FLIPPER_VERSION.*""' "$file"; then
          grep -n 'flipper\|Flipper' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [ERROR] Flipper dependency not excluded from release builds → Use debugImplementation instead of implementation for Flipper deps; including Flipper in release adds ~20MB and leaks debug info"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

echo ""
echo "Build configuration scan complete."

#!/bin/bash
# Image Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Image Performance Scanner"
echo "================================"

# <Image> without explicit width/height (layout thrash)
echo ""
echo "--- <Image> Without Explicit Dimensions ---"
grep -rn --include="*.tsx" --include="*.jsx" '<Image ' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 6))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'width\|height\|style='; then
        echo "$file:$lineno — [ERROR] <Image> without explicit width/height → Provide dimensions or a style with width/height to prevent layout recalculation"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Network images without placeholder/defaultSource/blurhash
echo ""
echo "--- Network Image Without Placeholder ---"
grep -rn --include="*.tsx" --include="*.jsx" 'source={{ uri:' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'defaultSource\|placeholder\|blurhash\|blurHash\|LoadingIndicator\|fallback'; then
        echo "$file:$lineno — [WARN] Network image without placeholder/defaultSource → Add defaultSource or blurhash to avoid blank flicker while loading"
        ISSUES=$((ISSUES + 1))
      fi
    done

# expo-image without cachePolicy
echo ""
echo "--- expo-image Without cachePolicy ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'expo-image\|from.*expo-image' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'cachePolicy' "$file"; then
        grep -n '<Image ' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [WARN] expo-image used without cachePolicy → Set cachePolicy='memory-disk' for best performance"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# Local require() for images
echo ""
echo "--- Local Image via require() ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "require('.*\.\(png\|jpg\|jpeg\|gif\|webp\)')\|require(\".*\.\(png\|jpg\|jpeg\|gif\|webp\)\")" \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      img_path=$(echo "$line" | grep -oE "require\(['\"]([^'\"]+)['\"]" | sed "s/require(['\"]//")
      if [ -n "$img_path" ]; then
        base_dir=$(dirname "$file")
        full_img="$base_dir/$img_path"
        if [ -f "$full_img" ]; then
          size=$(wc -c < "$full_img" 2>/dev/null || echo 0)
          if [ "$size" -gt 200000 ]; then
            echo "$file:$lineno — [WARN] Large local image ($(( size / 1024 ))KB) require() → Compress image, use @2x/@3x variants, or switch to WebP"
            ISSUES=$((ISSUES + 1))
          fi
        fi
      fi
      echo "$file:$lineno — [INFO] Local image via require() → Ensure image is optimized (compressed, correct resolution); use WebP format"
      ISSUES=$((ISSUES + 1))
    done

# <Image> without resizeMode/contentFit
echo ""
echo "--- <Image> Without resizeMode ---"
grep -rn --include="*.tsx" --include="*.jsx" '<Image ' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 6))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'resizeMode\|contentFit'; then
        echo "$file:$lineno — [INFO] <Image> without resizeMode/contentFit → Specify resizeMode to avoid unexpected stretching or cropping"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Using <Image> from react-native instead of expo-image or fast-image
echo ""
echo "--- react-native <Image> (Consider expo-image) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-native'" "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep 'Image' \
  | grep -v 'ImageBackground\|ImageStyle\|ImageSource\|ImageResizeMode\|ImageURISource\|ImageRequireSource' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] Using react-native <Image> → Consider expo-image or react-native-fast-image for better caching, blurhash support, and performance"
      ISSUES=$((ISSUES + 1))
    done

# GIF images (memory-heavy)
echo ""
echo "--- GIF Images (Memory-Heavy) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\.gif\|\.GIF' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] GIF image detected → GIFs are memory-heavy; use Lottie animations or video loops instead"
      ISSUES=$((ISSUES + 1))
    done

# Images in list without React.memo on item component
echo ""
echo "--- Images in List Without React.memo ---"
grep -rln --include="*.tsx" --include="*.jsx" \
  'FlatList\|FlashList\|SectionList' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q '<Image ' "$file" || grep -q 'expo-image' "$file"; then
        if ! grep -q 'React\.memo\|memo(' "$file"; then
          grep -n '<Image ' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [WARN] Image in list without React.memo on item component → Wrap list item component with React.memo to prevent unnecessary re-renders"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# <ImageBackground> used for decoration
echo ""
echo "--- <ImageBackground> (Use absolute <Image> Instead) ---"
grep -rn --include="*.tsx" --include="*.jsx" '<ImageBackground' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] <ImageBackground> detected → If used for decoration only, consider absolute-positioned <Image> inside a <View> for better compositing control"
      ISSUES=$((ISSUES + 1))
    done

echo ""
echo "Image scan complete."

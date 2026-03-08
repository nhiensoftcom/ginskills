#!/bin/bash
# Animation Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Animation Performance Scanner"
echo "================================"

# Animated.timing/spring/decay without useNativeDriver: true
# Note: useNativeDriver only supports opacity and transform. Properties like backgroundColor,
# width, height, margin, padding, borderRadius REQUIRE useNativeDriver: false — not a bug.
echo ""
echo "--- Animated Without useNativeDriver ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.timing(\|Animated\.spring(\|Animated\.decay(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      # Look at broader context (20 lines) to check what property the animated value drives
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      broad_context=$(sed -n "1,$((lineno + 30))p" "$file" 2>/dev/null | tail -50)
      if ! echo "$context" | grep -q 'useNativeDriver:\s*true'; then
        if echo "$context" | grep -q 'useNativeDriver:\s*false'; then
          # Check if the animated value is used for non-native-driver-compatible properties
          # (backgroundColor, width, height, margin*, padding*, border*, left, top, right, bottom, flex)
          if echo "$broad_context" | grep -qE 'backgroundColor|width:\s*anim|height:\s*anim|marginTop|marginBottom|marginLeft|marginRight|paddingTop|paddingBottom|paddingLeft|paddingRight|borderRadius|borderWidth|left:\s*anim|top:\s*anim|right:\s*anim|bottom:\s*anim|interpolate.*backgroundColor|interpolate.*color'; then
            echo "$file:$lineno — [INFO] Animated with useNativeDriver: false (justified: animates layout/color property) → Consider react-native-reanimated for smoother layout animations on UI thread"
          else
            echo "$file:$lineno — [ERROR] Animated.timing/spring with useNativeDriver: false → Change to useNativeDriver: true; only opacity and transform are supported on native thread"
          fi
        else
          echo "$file:$lineno — [ERROR] Animated.timing/spring missing useNativeDriver → Add useNativeDriver: true to run animation on UI thread and avoid JS thread jank"
        fi
        ISSUES=$((ISSUES + 1))
      fi
    done

# Animated.event without useNativeDriver
echo ""
echo "--- Animated.event Without useNativeDriver ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.event(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 5))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'useNativeDriver'; then
        echo "$file:$lineno — [ERROR] Animated.event without useNativeDriver → Add { useNativeDriver: true } as second argument"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Animated.parallel/sequence/stagger without useNativeDriver in child animations
echo ""
echo "--- Animated Composition Without useNativeDriver ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.parallel(\|Animated\.sequence(\|Animated\.stagger(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 15))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'useNativeDriver'; then
        echo "$file:$lineno — [WARN] Animated composition (parallel/sequence/stagger) without useNativeDriver in child animations → Ensure all child animations have useNativeDriver: true"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Heavy shadow styles (shadowOffset + shadowRadius together)
echo ""
echo "--- Heavy Shadow Styles ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'shadowOffset\|shadowRadius\|shadowOpacity\|shadowColor' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 3 ? lineno - 3 : 1)),$((lineno + 3))p" "$file" 2>/dev/null)
      shadow_props=$(echo "$context" | grep -Ec 'shadowOffset|shadowRadius|shadowOpacity|shadowColor' 2>/dev/null; true)
      if [ "$shadow_props" -ge 3 ]; then
        echo "$file:$lineno — [WARN] Complex iOS shadow (multiple shadow props) → Shadows on animated views cause off-screen compositing; use elevation on Android and pre-render shadows where possible"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Importing Animated from react-native (suggest Reanimated)
echo ""
echo "--- Animated from react-native (Consider Reanimated) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "from 'react-native'" "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep '\bAnimated\b' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [WARN] Importing Animated from 'react-native' → Consider react-native-reanimated for smoother animations and worklet-based execution on UI thread"
      ISSUES=$((ISSUES + 1))
    done

# Animating layout properties (width/height/top/left) instead of transform
echo ""
echo "--- Animating Layout Properties (Use transform) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.Value\|useSharedValue' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 20))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'width:\s*anim\|height:\s*anim\|top:\s*anim\|left:\s*anim\|marginTop:\s*anim\|paddingTop:\s*anim'; then
        echo "$file:$lineno — [ERROR] Animating layout properties (width/height/top/left) → Animating layout triggers re-layout; use transform: [{ translateX }] or opacity instead"
        ISSUES=$((ISSUES + 1))
      fi
    done

# setState inside animation .start() callback
echo ""
echo "--- setState in Animation .start() Callback ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\.start(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 5))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'setState\|set[A-Z]\|dispatch('; then
        echo "$file:$lineno — [WARN] setState called inside animation .start() callback → This is fine for completion, but avoid triggering heavy state updates that cause re-renders during animation"
        ISSUES=$((ISSUES + 1))
      fi
    done

# LottieView without explicit loop prop
echo ""
echo "--- LottieView Without loop Prop ---"
grep -rn --include="*.tsx" --include="*.jsx" \
  '<LottieView\|<AnimatedLottieView' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v 'useRef<\|useState<\|useMemo<\|useCallback<' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 6))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'loop='; then
        echo "$file:$lineno — [WARN] LottieView without explicit loop prop → Add loop={false} for one-shot animations to stop background rendering after completion"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Multiple Animated.View without hardware texture hints
echo ""
echo "--- Multiple Animated.View Without Hardware Texture Hints ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.View\|useAnimatedStyle' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      anim_count=$(grep -Ec '<Animated\.View|Animated\.createAnimatedComponent' "$file" 2>/dev/null; true)
      if [ "$anim_count" -gt 3 ]; then
        if ! grep -q 'shouldRasterizeIOS\|renderToHardwareTextureAndroid' "$file"; then
          grep -n '<Animated\.View' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [INFO] Multiple Animated.View without hardware texture hints → Consider shouldRasterizeIOS / renderToHardwareTextureAndroid on complex animated views"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Reanimated worklet calling non-worklet JS functions
echo ""
echo "--- Reanimated Worklet Calling JS Functions ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  "'worklet'" "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 15))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'console\.log\|setState\|dispatch\|fetch('; then
        echo "$file:$lineno — [ERROR] Non-worklet function call inside worklet → Only call functions marked as 'worklet' from within worklets; JS thread calls will cause errors/crashes"
        ISSUES=$((ISSUES + 1))
      fi
    done

# ScrollView without scrollEventThrottle prop
echo ""
echo "--- ScrollView Without scrollEventThrottle ---"
grep -rn --include="*.tsx" --include="*.jsx" \
  '<ScrollView' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      if echo "$context" | grep -q 'onScroll' && ! echo "$context" | grep -q 'scrollEventThrottle'; then
        echo "$file:$lineno — [WARN] ScrollView with onScroll but no scrollEventThrottle → Without scrollEventThrottle the onScroll fires on every frame; set scrollEventThrottle={16} to limit to 60fps"
        ISSUES=$((ISSUES + 1))
      fi
    done

# PanResponder created inside render (should be useMemo/useRef)
echo ""
echo "--- PanResponder Created Inside Render ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'PanResponder\.create(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 5 ? lineno - 5 : 1)),$((lineno + 2))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'useMemo\|useRef\|useCallback\|useEffect'; then
        echo "$file:$lineno — [ERROR] PanResponder.create() outside useMemo/useRef → PanResponder recreated on every render; wrap with useMemo(() => PanResponder.create(...), []) or store in useRef"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Animated.Value created inside render (should be useRef)
echo ""
echo "--- Animated.Value Created Inside Render ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'new Animated\.Value(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "$((lineno > 5 ? lineno - 5 : 1)),$((lineno + 1))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'useRef\|useMemo\|useState\|useSharedValue'; then
        echo "$file:$lineno — [ERROR] new Animated.Value() outside useRef/useState → Creates a new Animated.Value on every render, losing animation state; use useRef(new Animated.Value(0)) or useSharedValue(0)"
        ISSUES=$((ISSUES + 1))
      fi
    done

# interpolate() with extreme ranges (precision loss)
echo ""
echo "--- interpolate() With Extreme Input/Output Ranges ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\.interpolate(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      if echo "$context" | grep -qE '[0-9]{5,}'; then
        echo "$file:$lineno — [WARN] interpolate() with very large numeric range → Extreme ranges (>10000) can cause floating-point precision loss in animations; normalize to a 0-1 range and scale in outputRange"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "Animation scan complete."

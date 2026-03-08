#!/bin/bash
# Navigation Performance Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Navigation Performance Scanner"
echo "================================"

# createStackNavigator (JS-based, should use createNativeStackNavigator)
echo ""
echo "--- createStackNavigator (JS-based) ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'createStackNavigator' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [ERROR] createStackNavigator uses JS-based transitions → Replace with createNativeStackNavigator from @react-navigation/native-stack for native performance"
      ISSUES=$((ISSUES + 1))
    done

# Tab/Drawer navigator without lazy: true
echo ""
echo "--- Tab/Drawer Navigator Without lazy: true ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'createBottomTabNavigator\|createDrawerNavigator\|createMaterialTopTabNavigator\|createMaterialBottomTabNavigator' \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'lazy.*true\|lazy: true' "$file"; then
        grep -n 'createBottomTabNavigator\|createDrawerNavigator\|createMaterialTopTabNavigator\|createMaterialBottomTabNavigator' "$file" \
          | while IFS= read -r match; do
              lineno=$(echo "$match" | cut -d: -f1)
              echo "$file:$lineno — [WARN] Tab/Drawer navigator without lazy: true → Add lazy: true in screenOptions to defer screen rendering"
              ISSUES=$((ISSUES + 1))
            done
      fi
    done

# Deep navigator nesting (>3 navigator instances in one file)
echo ""
echo "--- Deep Navigator Nesting ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '<Stack\.Navigator\|<Tab\.Navigator\|<Drawer\.Navigator\|<NativeStack\.Navigator' \
  "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      depth=$(grep -c '<Stack\.Navigator\|<Tab\.Navigator\|<Drawer\.Navigator\|<NativeStack\.Navigator' "$file" 2>/dev/null || echo 0)
      if [ "$depth" -gt 3 ]; then
        grep -n '<Stack\.Navigator\|<Tab\.Navigator\|<Drawer\.Navigator\|<NativeStack\.Navigator' "$file" \
          | head -1 | while IFS= read -r match; do
              lineno=$(echo "$match" | cut -d: -f1)
              echo "$file:$lineno — [WARN] File has $depth nested navigators → Deep nesting increases TTI; flatten structure"
              ISSUES=$((ISSUES + 1))
            done
      fi
    done

# useEffect with fetch/API calls in screen (should use useFocusEffect)
echo ""
echo "--- useEffect for Data Fetching (Use useFocusEffect) ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useEffect\|useNavigation\|useFocusEffect' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useNavigation\|useRoute' "$file" \
         && grep -q 'useEffect' "$file" \
         && ! grep -q 'useFocusEffect' "$file"; then
        if grep -q 'fetch(\|axios\.\|api\.\|query\|load\|getData\|fetchData' "$file"; then
          grep -n 'useEffect(' "$file" | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [WARN] useEffect for data fetching in a screen → Use useFocusEffect to re-fetch only when screen is focused"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Missing enableScreens import near NavigationContainer
echo ""
echo "--- Missing enableScreens() ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'NavigationContainer' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'enableScreens' "$file"; then
        app_dir=$(dirname "$file")
        if ! grep -rl 'enableScreens' "$app_dir" > /dev/null 2>&1; then
          grep -n 'NavigationContainer' "$file" | head -1 | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [ERROR] NavigationContainer found but enableScreens() not called → Add enableScreens() from react-native-screens before NavigationContainer"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Heavy operations in useEffect on screen mount without InteractionManager
echo ""
echo "--- Heavy Mount Operations Without InteractionManager ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useNavigation\|useRoute' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useEffect' "$file" && ! grep -q 'InteractionManager\.runAfterInteractions' "$file"; then
        grep -n 'useEffect(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          context=$(sed -n "${lineno},$((lineno + 15))p" "$file" 2>/dev/null)
          if echo "$context" | grep -q 'fetch(\|axios\|load\|query\|parse\|heavy\|compute'; then
            echo "$file:$lineno — [INFO] Heavy operation in useEffect on screen mount → Consider InteractionManager.runAfterInteractions to defer until after transition"
            ISSUES=$((ISSUES + 1))
          fi
        done
      fi
    done

# navigation.navigate() calls (informational — remind about stable params)
echo ""
echo "--- navigation.navigate() Param Stability ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'navigation\.navigate(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | grep -v '//' \
  | while IFS= read -r line; do
      file_loc=$(echo "$line" | cut -d: -f1,2)
      echo "$file_loc — [INFO] navigation.navigate() call → Ensure params objects are stable (not inline) to avoid unnecessary re-renders in target screen"
      ISSUES=$((ISSUES + 1))
    done

# headerShown not set on screen options
echo ""
echo "--- Screen Options Without Explicit headerShown ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'screenOptions=\|<Stack\.Screen\|<NativeStack\.Screen' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 5))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'headerShown'; then
        echo "$file:$lineno — [INFO] Screen options without explicit headerShown → Set headerShown: false on screens with custom headers to avoid double-render"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Navigator created inside component (should be at module level)
echo ""
echo "--- Navigator Created Inside Component ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'create.*Navigator(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      open_braces=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null | tr -cd '{' | wc -c | tr -d ' ')
      close_braces=$(sed -n "1,$((lineno - 1))p" "$file" 2>/dev/null | tr -cd '}' | wc -c | tr -d ' ')
      depth=$((open_braces - close_braces))
      if [ "$depth" -gt 0 ]; then
        echo "$file:$lineno — [ERROR] Navigator created inside a function/component body → Move createXxxNavigator() calls to module scope; recreating navigators on render resets navigation state"
        ISSUES=$((ISSUES + 1))
      fi
    done

# navigation.navigate with large params objects
echo ""
echo "--- navigation.navigate With Inline Object Params ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'navigation\.navigate(.*{' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno}p" "$file" 2>/dev/null)
      param_count=$(echo "$context" | grep -oE '[a-zA-Z]+:' | wc -l | tr -d ' ')
      if [ "$param_count" -gt 3 ]; then
        echo "$file:$lineno — [WARN] navigation.navigate with large inline params object ($param_count keys) → Large param objects are serialized/deserialized on each navigation; pass an ID and fetch data in the target screen"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Missing gestureEnabled configuration
echo ""
echo "--- Screen Without gestureEnabled Configuration ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '<Stack\.Screen\|<NativeStack\.Screen' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 8))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'gestureEnabled\|gestureDirection'; then
        echo "$file:$lineno — [INFO] Stack.Screen without gestureEnabled → Explicitly set gestureEnabled: false on modal or onboarding screens to prevent accidental swipe-back dismissal"
        ISSUES=$((ISSUES + 1))
      fi
    done

# Tab.Screen without lazy prop
echo ""
echo "--- Tab.Screen Without lazy Prop ---"
grep -rn --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '<Tab\.Screen\|<BottomTab\.Screen\|<MaterialTopTab\.Screen' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r line; do
      file=$(echo "$line" | cut -d: -f1)
      lineno=$(echo "$line" | cut -d: -f2)
      context=$(sed -n "${lineno},$((lineno + 5))p" "$file" 2>/dev/null)
      parent_context=$(sed -n "$((lineno > 20 ? lineno - 20 : 1)),$((lineno - 1))p" "$file" 2>/dev/null)
      if ! echo "$context" | grep -q 'lazy' && ! echo "$parent_context" | grep -q 'lazy.*true\|lazy: true'; then
        echo "$file:$lineno — [WARN] Tab.Screen without lazy prop → Tab screens render eagerly by default; set lazy={true} in screenOptions to defer rendering until the tab is visited"
        ISSUES=$((ISSUES + 1))
      fi
    done

echo ""
echo "Navigation scan complete."

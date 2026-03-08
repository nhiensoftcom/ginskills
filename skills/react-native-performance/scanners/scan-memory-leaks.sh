#!/bin/bash
# Memory Leak Scanner
DIR="${1:-./src}"
ISSUES=0

echo "Memory Leak Scanner"
echo "================================"

# addEventListener without removeEventListener / subscription.remove() in useEffect
echo ""
echo "--- addEventListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'addEventListener' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'useEffect' "$file"; then
        # Accept removeEventListener (DOM) or .remove() (React Native subscription API)
        if ! grep -q 'removeEventListener\|\.remove()' "$file"; then
          grep -n 'addEventListener' "$file" | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [ERROR] addEventListener without removeEventListener in cleanup → Return cleanup function calling removeEventListener"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# addListener without remove
echo ""
echo "--- addListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" '\.addListener(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.remove()\|removeListener\|removeAllListeners' "$file"; then
        grep -n '\.addListener(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] addListener() without cleanup → Store subscription and call .remove() in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# setInterval without clearInterval (only inside React components/hooks, not plain class services)
echo ""
echo "--- setInterval Without clearInterval ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'setInterval(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      # Only flag files that also use useEffect — plain service classes manage their own timers
      if grep -q 'useEffect' "$file" && ! grep -q 'clearInterval' "$file"; then
        grep -n 'setInterval(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] setInterval without clearInterval → Return () => clearInterval(id) from useEffect"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# setTimeout inside useEffect without clearTimeout
# Only flags when setTimeout appears within 5 lines after a useEffect call (scoped to effect body)
echo ""
echo "--- setTimeout Without clearTimeout ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'setTimeout(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'clearTimeout' "$file"; then
        # Only flag setTimeout that appears within a useEffect body (within 5 lines after useEffect)
        grep -n 'useEffect(' "$file" | while IFS= read -r ueline; do
          uelineno=$(echo "$ueline" | cut -d: -f1)
          endlineno=$((uelineno + 5))
          block=$(sed -n "${uelineno},${endlineno}p" "$file" 2>/dev/null)
          if echo "$block" | grep -q 'setTimeout('; then
            # Report the useEffect line so the developer sees where to add cleanup
            echo "$file:$uelineno — [WARN] setTimeout inside useEffect without clearTimeout → Store ref and call clearTimeout in useEffect cleanup"
            ISSUES=$((ISSUES + 1))
          fi
        done
      fi
    done

# .subscribe() without .unsubscribe()
echo ""
echo "--- subscribe() Without unsubscribe() ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" '\.subscribe(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.unsubscribe()\|subscription\.remove\|cleanup\|return.*unsub' "$file"; then
        grep -n '\.subscribe(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] .subscribe() without .unsubscribe() → Call subscription.unsubscribe() in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# fetch() inside useEffect without AbortController
# Uses [^a-zA-Z]fetch( to exclude refetch(), prefetch(), etc.
echo ""
echo "--- fetch Without AbortController ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'useEffect' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'AbortController\|signal\|abortController' "$file"; then
        # Walk each useEffect block: check the 30 lines after it for a bare fetch() call
        grep -n 'useEffect(' "$file" | while IFS= read -r ueline; do
          uelineno=$(echo "$ueline" | cut -d: -f1)
          endlineno=$((uelineno + 30))
          block=$(sed -n "${uelineno},${endlineno}p" "$file" 2>/dev/null)
          # Exclude refetch(, prefetch(, etc. — only match fetch( not preceded by a word char
          if echo "$block" | grep -qE '[^a-zA-Z]fetch\(|^fetch\('; then
            echo "$file:$uelineno — [WARN] fetch() in useEffect without AbortController → Add AbortController and return cleanup calling abort()"
            ISSUES=$((ISSUES + 1))
          fi
        done
      fi
    done

# WebSocket without .close()
echo ""
echo "--- WebSocket Without .close() ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'new WebSocket(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.close()\|ws\.close\|socket\.close\|websocket\.close' "$file"; then
        grep -n 'new WebSocket(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] WebSocket created without .close() in cleanup → Return () => ws.close() from useEffect"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# Animated.Value.addListener without removeListener
echo ""
echo "--- Animated.Value Listener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'Animated\.Value\|useAnimatedValue\|new Animated\.' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q '\.addListener(' "$file" && ! grep -q '\.removeListener(\|\.removeAllListeners(' "$file"; then
        grep -n '\.addListener(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] Animated.Value.addListener without removeListener → Call animated.removeListener(id) in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# NOTE: A generic "useEffect with subscription but no cleanup return" heuristic is intentionally
# omitted. Without a real JS parser, any line-count-based approximation produces too many false
# positives from nested callbacks and adjacent effects. The dedicated checks above (addListener,
# subscribe, addEventListener, setInterval, AppState) catch these patterns more reliably.

# AppState.addEventListener without remove
echo ""
echo "--- AppState.addEventListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'AppState' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'AppState\.addEventListener\|AppState\.addListener' "$file" \
         && ! grep -q '\.remove()\|removeEventListener' "$file"; then
        grep -n 'AppState\.addEventListener\|AppState\.addListener' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] AppState.addEventListener without cleanup → Store subscription and call subscription.remove() in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# Keyboard.addListener without remove
echo ""
echo "--- Keyboard.addListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" 'Keyboard\.addListener' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.remove()\|Keyboard\.removeListener\|Keyboard\.removeAllListeners' "$file"; then
        grep -n 'Keyboard\.addListener' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] Keyboard.addListener without cleanup → Call subscription.remove() in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# DeviceEventEmitter.addListener without cleanup
echo ""
echo "--- DeviceEventEmitter.addListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'DeviceEventEmitter\.addListener' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.remove()\|DeviceEventEmitter\.removeListener\|DeviceEventEmitter\.removeAllListeners' "$file"; then
        grep -n 'DeviceEventEmitter\.addListener' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] DeviceEventEmitter.addListener without cleanup → Store the subscription and call subscription.remove() in useEffect cleanup"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# navigation.addListener without cleanup
echo ""
echo "--- navigation.addListener Without Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'navigation\.addListener(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q '\.remove()\|removeListener\|return.*unsubscribe\|return.*remove' "$file"; then
        grep -n 'navigation\.addListener(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [ERROR] navigation.addListener without cleanup → navigation.addListener returns an unsubscribe function; return it from useEffect"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

# EventEmitter.on() without .off()
echo ""
echo "--- EventEmitter.on() Without .off() ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  '\bon(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if grep -q 'EventEmitter\|emitter\.' "$file"; then
        if ! grep -q '\.off(\|\.removeListener(\|\.removeAllListeners(' "$file"; then
          grep -n '\.on(' "$file" | while IFS= read -r match; do
            lineno=$(echo "$match" | cut -d: -f1)
            echo "$file:$lineno — [ERROR] EventEmitter.on() without corresponding .off() → Call emitter.off(event, handler) in useEffect cleanup to prevent listener accumulation"
            ISSUES=$((ISSUES + 1))
          done
        fi
      fi
    done

# Reanimated useAnimatedReaction without cancelAnimation cleanup
echo ""
echo "--- useAnimatedReaction Without cancelAnimation Cleanup ---"
grep -rln --include="*.tsx" --include="*.ts" --include="*.jsx" --include="*.js" \
  'useAnimatedReaction(' "$DIR" 2>/dev/null \
  | grep -v node_modules | grep -v '__tests__' | grep -v '\.test\.' | grep -v '\.spec\.' \
  | while IFS= read -r file; do
      if ! grep -q 'cancelAnimation' "$file"; then
        grep -n 'useAnimatedReaction(' "$file" | while IFS= read -r match; do
          lineno=$(echo "$match" | cut -d: -f1)
          echo "$file:$lineno — [WARN] useAnimatedReaction without cancelAnimation cleanup → If the reaction drives an animation, call cancelAnimation(sharedValue) in the cleanup callback to prevent leaked animations"
          ISSUES=$((ISSUES + 1))
        done
      fi
    done

echo ""
echo "Memory leak scan complete."

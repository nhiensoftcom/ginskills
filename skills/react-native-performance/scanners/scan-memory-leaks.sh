#!/bin/bash
# React Native Memory Leak Scanner
DIR="${1:-.}"
EXT="--include=*.tsx --include=*.ts --include=*.jsx --include=*.js"

echo "Scanning for memory leak patterns in $DIR..."
echo "=================================================="

# 1. addEventListener without removeEventListener in useEffect
# Find files that have addEventListener inside useEffect
grep -rln $EXT 'addEventListener' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'useEffect' "$file"; then
    if ! grep -q 'removeEventListener' "$file"; then
      grep -n 'addEventListener' "$file" | while IFS= read -r match; do
        lineno=$(echo "$match" | cut -d: -f1)
        echo "$file:$lineno — [ERROR] addEventListener without removeEventListener in cleanup → Return cleanup function calling removeEventListener"
      done
    fi
  fi
done

# 2. addListener without remove / removeListener / removeAllListeners
grep -rln $EXT '\.addListener(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q '\.remove()\|removeListener\|removeAllListeners' "$file"; then
    grep -n '\.addListener(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] addListener() without cleanup → Store subscription and call .remove() in useEffect cleanup"
    done
  fi
done

# 3. setInterval without clearInterval in cleanup
grep -rln $EXT 'setInterval(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q 'clearInterval' "$file"; then
    grep -n 'setInterval(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] setInterval without clearInterval → Return () => clearInterval(id) from useEffect"
    done
  fi
done

# 4. setTimeout without clearTimeout in cleanup (only flag when inside useEffect-like patterns)
grep -rln $EXT 'setTimeout(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'useEffect' "$file" && ! grep -q 'clearTimeout' "$file"; then
    grep -n 'setTimeout(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [WARN] setTimeout inside component without clearTimeout → Store ref and clear in useEffect cleanup"
    done
  fi
done

# 5. .subscribe() without .unsubscribe() (RxJS, Zustand, etc.)
grep -rln $EXT '\.subscribe(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q '\.unsubscribe()\|subscription\.remove\|cleanup\|return.*unsub' "$file"; then
    grep -n '\.subscribe(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] .subscribe() without .unsubscribe() → Call subscription.unsubscribe() in useEffect cleanup"
    done
  fi
done

# 6. fetch inside useEffect without AbortController
grep -rln $EXT 'useEffect' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'fetch(' "$file" && ! grep -q 'AbortController\|signal\|abortController' "$file"; then
    grep -n 'fetch(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [WARN] fetch() in useEffect without AbortController → Add AbortController and return cleanup calling abort()"
    done
  fi
done

# 7. new WebSocket without .close() in cleanup
grep -rln $EXT 'new WebSocket(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q '\.close()\|ws\.close\|socket\.close\|websocket\.close' "$file"; then
    grep -n 'new WebSocket(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] WebSocket created without .close() in cleanup → Return () => ws.close() from useEffect"
    done
  fi
done

# 8. Animated.Value.addListener without removeListener
grep -rln $EXT 'Animated\.Value\|useAnimatedValue\|new Animated\.' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q '\.addListener(' "$file" && ! grep -q '\.removeListener(\|\.removeAllListeners(' "$file"; then
    grep -n '\.addListener(' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] Animated.Value.addListener without removeListener → Call animated.removeListener(id) in useEffect cleanup"
    done
  fi
done

# 9. AppState.addEventListener without remove (React Native AppState)
grep -rln $EXT 'AppState' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'AppState\.addEventListener\|AppState\.addListener' "$file" && ! grep -q '\.remove()\|removeEventListener' "$file"; then
    grep -n 'AppState\.addEventListener\|AppState\.addListener' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] AppState.addEventListener without cleanup → Store subscription and call subscription.remove() in useEffect cleanup"
    done
  fi
done

# 10. Keyboard.addListener without remove
grep -rln $EXT 'Keyboard\.addListener' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if ! grep -q '\.remove()\|Keyboard\.removeListener\|Keyboard\.removeAllListeners' "$file"; then
    grep -n 'Keyboard\.addListener' "$file" | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [ERROR] Keyboard.addListener without cleanup → Call subscription.remove() in useEffect cleanup"
    done
  fi
done

# 11. useEffect blocks that have side-effect calls but no return statement (heuristic)
grep -rn $EXT 'useEffect(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  lineno=$(echo "$line" | cut -d: -f2)
  # Check next 20 lines for subscription pattern with no return
  context=$(sed -n "$((lineno)),$((lineno + 20))p" "$file" 2>/dev/null)
  if echo "$context" | grep -q 'subscribe\|addListener\|addEventListener\|setInterval\|setTimeout'; then
    if ! echo "$context" | grep -q 'return\s*()'; then
      echo "$file:$lineno — [WARN] useEffect with subscription/listener may be missing cleanup return → Add return () => { ... } cleanup"
    fi
  fi
done

# 12. Event emitter patterns (EventEmitter.on) without .off
grep -rln $EXT '\.on(' "$DIR" \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  --exclude="*.test.*" \
  --exclude="*.spec.*" | while IFS= read -r file; do
  if grep -q 'EventEmitter\|emitter\|mitt\|eventemitter' "$file" && ! grep -q '\.off(\|\.removeListener(' "$file"; then
    grep -n '\.on(' "$file" | grep -v '//\|console\|_on\|upon\|icon\|button\|option\|position\|action\|section\|function\|emotion' | while IFS= read -r match; do
      lineno=$(echo "$match" | cut -d: -f1)
      echo "$file:$lineno — [WARN] EventEmitter.on() without .off() → Call emitter.off(event, handler) in cleanup"
    done
  fi
done

echo ""
echo "Scan complete."

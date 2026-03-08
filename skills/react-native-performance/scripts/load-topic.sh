#!/bin/bash
# load-topic.sh — Routes to the right performance doc based on topic argument.
# Used by SKILL.md via !`command` dynamic context injection.
#
# Usage: load-topic.sh [topic]
# Topics: architecture | rendering | startup | memory | navigation | network-state |
#         bundle | algorithms | animations | senior | anti-patterns | monitoring |
#         checklist | scan | scan-all

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOPIC="${1:-index}"

# Normalize: lowercase, strip leading /, trim
TOPIC=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed 's|^/||' | xargs)

case "$TOPIC" in
  arch|architecture|new-arch|jsi|fabric|turbo|hermes|bridgeless|metro)
    cat "$SKILL_DIR/docs/01-architecture.md"
    ;;
  render|rendering|rerender|re-render|memo|flashlist|flatlist|image|images|expo-image)
    cat "$SKILL_DIR/docs/02-rendering.md"
    ;;
  startup|cold-start|tti|splash|lazy|inline-requires|boot)
    cat "$SKILL_DIR/docs/03-startup.md"
    ;;
  memory|leak|leaks|memory-leak|gc|garbage|heap|ram)
    cat "$SKILL_DIR/docs/04-memory.md"
    ;;
  nav|navigation|navigate|screen|transition|focus|stack|tab)
    cat "$SKILL_DIR/docs/05-navigation.md"
    ;;
  network|state|zustand|redux|query|tanstack|fetch|api|cache|caching)
    cat "$SKILL_DIR/docs/06-network-state.md"
    ;;
  bundle|tree-shaking|treeshake|size|split|code-split|dead-code|metro-config)
    cat "$SKILL_DIR/docs/07-bundle-size.md"
    ;;
  algo|algorithm|algorithms|data-structure|sort|search|big-o|concurrency|thread)
    cat "$SKILL_DIR/docs/08-algorithms.md"
    ;;
  anim|animation|animations|reanimated|gesture|scroll|lottie|skia)
    cat "$SKILL_DIR/docs/09-animations.md"
    ;;
  senior|tricks|advanced|hidden|expert|pro|native-level|expo)
    cat "$SKILL_DIR/docs/10-senior-tricks.md"
    ;;
  anti|anti-pattern|anti-patterns|mistakes|bad|wrong|dont|avoid)
    cat "$SKILL_DIR/docs/11-anti-patterns.md"
    ;;
  monitor|monitoring|profil|profiling|sentry|instruments|devtools|ci|test|benchmark)
    cat "$SKILL_DIR/docs/12-monitoring.md"
    ;;
  checklist|check|audit|todo|level|effort|quick-win)
    cat "$SKILL_DIR/docs/13-checklist.md"
    ;;
  scan|scanner|scan-all|detect|lint|perf-lint)
    echo "## Available Performance Scanners"
    echo ""
    echo "Run these scripts to detect performance issues in your codebase:"
    echo ""
    echo '```bash'
    echo "# Run ALL scanners (recommended)"
    echo "bash $SKILL_DIR/scanners/scan-all.sh /path/to/your/rn/src"
    echo ""
    echo "# Run individual scanners"
    echo "bash $SKILL_DIR/scanners/scan-rendering.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-memory-leaks.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-bundle-size.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-navigation.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-state-network.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-images.sh /path/to/src"
    echo "bash $SKILL_DIR/scanners/scan-animations.sh /path/to/src"
    echo '```'
    echo ""
    echo "Each scanner outputs: file:line — [SEVERITY] description → suggested fix"
    ;;
  *)
    # Default: show the index/overview
    echo "## React Native Performance — Topic Index"
    echo ""
    echo "Load a specific topic for detailed guidance:"
    echo ""
    echo "| Topic | Command | What You'll Learn |"
    echo "|-------|---------|-------------------|"
    echo "| Architecture | \`/react-native-performance architecture\` | New Arch, Hermes, JSI, Fabric, TurboModules |"
    echo "| Rendering | \`/react-native-performance rendering\` | Re-renders, FlashList, images, React.memo |"
    echo "| Startup | \`/react-native-performance startup\` | Cold start, TTI, splash, lazy loading |"
    echo "| Memory | \`/react-native-performance memory\` | Leaks, GC, detection, budgets, fixes |"
    echo "| Navigation | \`/react-native-performance navigation\` | Screen transitions, focus, native-stack |"
    echo "| Network & State | \`/react-native-performance network\` | Zustand, TanStack Query, caching |"
    echo "| Bundle Size | \`/react-native-performance bundle\` | Tree shaking, analysis, code splitting |"
    echo "| Algorithms | \`/react-native-performance algorithms\` | Data structures, Big-O, concurrency |"
    echo "| Animations | \`/react-native-performance animations\` | Reanimated, gestures, scroll, 120fps |"
    echo "| Senior Tricks | \`/react-native-performance senior\` | Hidden killers, native-level, Expo |"
    echo "| Anti-Patterns | \`/react-native-performance anti-patterns\` | Quick reference of all bad patterns |"
    echo "| Monitoring | \`/react-native-performance monitoring\` | Profiling, Sentry, CI benchmarks |"
    echo "| Checklist | \`/react-native-performance checklist\` | Optimization by effort level |"
    echo "| Scanners | \`/react-native-performance scan\` | Auto-detect perf issues in codebase |"
    echo ""
    echo "---"
    echo ""
    echo "**For AI agents**: Read specific docs directly from \`docs/\` folder:"
    echo '```'
    echo "Read docs/01-architecture.md   — when optimizing app architecture"
    echo "Read docs/04-memory.md         — when debugging memory leaks"
    echo "Read docs/07-bundle-size.md    — when reducing app size"
    echo "Read docs/11-anti-patterns.md  — when doing code review"
    echo '```'
    ;;
esac

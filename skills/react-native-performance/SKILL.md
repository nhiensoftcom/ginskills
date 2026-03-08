---
name: react-native-performance
description: |
  **React Native Performance Optimization**: Comprehensive guide — rendering, memory leaks, bundle size, startup, animations, navigation, algorithms, and automated codebase scanners. 13 deep-dive topics with 8 scanner scripts.
  - MANDATORY TRIGGERS: react native performance, RN performance, optimize react native, slow app, memory leak, bundle size, startup time, TTI, FPS, jank, re-render, FlashList, tree shaking, Hermes, Reanimated, performance budget, scroll performance, animation performance, app size, cold start, laggy, frame drop, JS thread, UI thread, react native slow
  - Use this skill whenever the user is optimizing React Native performance, debugging jank or memory issues, reviewing code for performance anti-patterns, or scanning codebases for performance problems.
argument-hint: "[architecture | rendering | startup | memory | navigation | network | bundle | algorithms | animations | senior | anti-patterns | monitoring | checklist | scan]"
disable-model-invocation: false
---

# React Native Performance Optimization

Load the relevant topic:

!`bash skills/skills/react-native-performance/scripts/load-topic.sh $ARGUMENTS`

---

## Skill Architecture (for AI agents)

This is a **multi-file skill**. Each topic is a standalone doc file — load ONLY what you need:

```
docs/01-architecture.md   → New Architecture, Hermes, JSI, Fabric, TurboModules, Metro
docs/02-rendering.md      → Re-renders, React.memo, FlashList, images, lists
docs/03-startup.md        → Cold start lifecycle, TTI, splash, lazy loading, defer init
docs/04-memory.md         → 22 memory leak patterns, detection, GC tuning, budgets, fixes
docs/05-navigation.md     → Native-stack, transitions, focus effects, screen preloading
docs/06-network-state.md  → Zustand, TanStack Query, caching, offline, WebSocket
docs/07-bundle-size.md    → Tree shaking, Metro config, heavy deps, code splitting, analysis
docs/08-algorithms.md     → Data structures, Big-O, sorting, caching, concurrency, threading
docs/09-animations.md     → Reanimated 3/4, gestures, scroll-linked, Skia, 120fps
docs/10-senior-tricks.md  → Hidden killers, native opts, build opts, Expo, case studies
docs/11-anti-patterns.md  → Complete anti-pattern table (30+ patterns with fixes)
docs/12-monitoring.md     → Profiling tools, Sentry, Reassure, Flashlight, CI integration
docs/13-checklist.md      → Optimization checklist by effort level (L1–L4)
```

### Multi-Agent Workflow
When reviewing a large codebase for performance, spawn agents per topic:
- **Agent 1**: Read `docs/04-memory.md` → scan for memory leaks
- **Agent 2**: Read `docs/07-bundle-size.md` → analyze bundle
- **Agent 3**: Read `docs/02-rendering.md` + `docs/11-anti-patterns.md` → review rendering
- **Agent 4**: Run `scanners/scan-all.sh ./src` → automated detection

### Automated Scanners

```bash
# Run ALL 8 scanners at once
bash skills/skills/react-native-performance/scanners/scan-all.sh ./src

# Individual scanners
bash scanners/scan-rendering.sh ./src        # Inline styles, missing memo, key={index}
bash scanners/scan-memory-leaks.sh ./src     # Missing cleanup, timers, listeners
bash scanners/scan-bundle-size.sh ./src      # Heavy imports, barrel files, dead code
bash scanners/scan-navigation.sh ./src       # Deep nesting, missing lazy, JS stack
bash scanners/scan-state-network.sh ./src    # Context abuse, missing selectors, waterfall
bash scanners/scan-images.sh ./src           # Missing cache, no dimensions, full-res
bash scanners/scan-animations.sh ./src       # Missing native driver, JS animations
bash scanners/scan-console-devtools.sh ./src # console.log, __DEV__ checks
```

Output format: `file:line — [ERROR|WARN|INFO] description → fix`

### Performance Budgets (Quick Reference)

| Metric | Good | Warning | Fail |
|--------|------|---------|------|
| Cold Start TTI | ≤1.5s iOS / ≤2.0s Android | ≤2.5s | >3.0s |
| Screen Transition | ≤300ms | ≤500ms | >700ms |
| List Scroll FPS | 60 FPS | 50-59 | <50 |
| Memory Peak | ≤200MB (3GB) | ≤350MB | >400MB |
| JS Bundle (gzip) | ≤2 MB | ≤4 MB | >6 MB |
| App Install Size | ≤20 MB AAB | ≤50 MB | >80 MB |

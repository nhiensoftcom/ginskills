#!/usr/bin/env bash
# load-docs.sh — Load a specific react-fsd-architecture doc file on demand.
# Usage: bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh <topic>
#
# Topics (keyword → file):
#   core, fsd, layers, slices, segments, architecture, structure
#       → docs/core-concepts.md
#   entity, entities, api, apis, hook, query, mutation, type, payload
#       → docs/entity-conventions.md
#   form, rhf, react-hook-form, zod, layer1, layer2, layer3, defaultValues, fieldArray, edit, dialog
#       → docs/form-architecture.md
#   list, table, tanstack, bulk, selection, column, columnDef, dialog-store, row
#       → docs/list-architecture.md
#   anti, antipattern, mistake, wrong, never, avoid
#       → docs/anti-patterns.md

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARG="${1:-help}"

case "$ARG" in
  core|fsd|layers|slices|segments|architecture|structure|import|rule|golden)
    cat "$SKILL_DIR/docs/core-concepts.md"
    ;;
  entity|entities|api|apis|hook|query|mutation|type|payload|qk|querykey|manual|repository)
    cat "$SKILL_DIR/docs/entity-conventions.md"
    ;;
  form|rhf|react-hook-form|zod|layer1|layer2|layer3|defaultvalues|fieldarray|edit|dialog|submit|async)
    cat "$SKILL_DIR/docs/form-architecture.md"
    ;;
  list|table|tanstack|bulk|selection|column|columndef|dialog-store|row|checkbox|rowaction|actions)
    cat "$SKILL_DIR/docs/list-architecture.md"
    ;;
  anti|antipattern|mistake|wrong|never|avoid|violation|bad)
    cat "$SKILL_DIR/docs/anti-patterns.md"
    ;;
  all)
    cat "$SKILL_DIR/docs/core-concepts.md"
    echo ""
    cat "$SKILL_DIR/docs/entity-conventions.md"
    echo ""
    cat "$SKILL_DIR/docs/form-architecture.md"
    echo ""
    cat "$SKILL_DIR/docs/list-architecture.md"
    echo ""
    cat "$SKILL_DIR/docs/anti-patterns.md"
    ;;
  *)
    echo "react-fsd-architecture docs — available topics:"
    echo ""
    echo "  core        → FSD layers, slices, segments, import rules"
    echo "  entity      → Entity folder structure, API hooks, types, payload types"
    echo "  form        → 3-layer RHF pattern, async defaultValues, useFieldArray"
    echo "  list        → TanStack Table, bulk actions, dialog store, column defs"
    echo "  anti        → Consolidated anti-patterns list"
    echo "  all         → Load all docs"
    echo ""
    echo "Usage: bash ginskills/skills/react-fsd-architecture/scripts/load-docs.sh <topic>"
    ;;
esac

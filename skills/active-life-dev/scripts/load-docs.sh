#!/bin/bash
# load-docs.sh — Loads the right documentation based on the topic argument.
# Used by active-life-dev SKILL.md via !`command` dynamic context injection.
#
# Usage: load-docs.sh [topic]
# Topics: module|schema|auth|patterns|integrations|setup|orders|products|inventory|vouchers|customers|all

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOPIC="${1:-overview}"

# Normalize: lowercase, strip leading /, trim spaces
TOPIC=$(echo "$TOPIC" | tr '[:upper:]' '[:lower:]' | sed 's|^/||' | xargs)

case "$TOPIC" in
  module|modules|controller|service|dto|feature)
    cat "$SKILL_DIR/docs/modules.md"
    ;;
  schema|database|db|prisma|model|models|table|tables|enum|enums|migration)
    cat "$SKILL_DIR/docs/schema.md"
    ;;
  auth|authentication|jwt|guard|guards|passport|login|register|role|roles|decorator|decorators)
    cat "$SKILL_DIR/docs/auth.md"
    ;;
  pattern|patterns|convention|conventions|code|coding|style|structure)
    cat "$SKILL_DIR/docs/patterns.md"
    ;;
  integration|integrations|etelecom|firebase|redis|email|mailer|mongoose|external)
    cat "$SKILL_DIR/docs/integrations.md"
    ;;
  setup|env|environment|config|configuration|install|deploy|supabase|script|scripts)
    cat "$SKILL_DIR/docs/setup.md"
    ;;
  order|orders|refund|return|payment|checkout|order-flow|order-status)
    cat "$SKILL_DIR/docs/orders.md"
    ;;
  product|products|combo|combos|category|categories|brand|brands|catalog)
    cat "$SKILL_DIR/docs/products.md"
    ;;
  inventory|warehouse|stock|lot|import|export|session|transaction)
    cat "$SKILL_DIR/docs/inventory.md"
    ;;
  voucher|vouchers|reward|rewards|spin|promotion|discount|redeem|point|points)
    cat "$SKILL_DIR/docs/vouchers.md"
    ;;
  customer|customers|client|clients|source|status|interaction|crm|bank)
    cat "$SKILL_DIR/docs/customers.md"
    ;;
  all)
    echo "=== ALL DOCUMENTATION ==="
    for f in "$SKILL_DIR"/docs/*.md; do
      echo ""
      echo "================================================================"
      echo "FILE: $(basename "$f")"
      echo "================================================================"
      cat "$f"
    done
    ;;
  *)
    # Default: show overview (just list available docs)
    echo "## Available Documentation Topics"
    echo ""
    echo "Use /active-life-dev [topic] to load specific docs:"
    echo ""
    echo "  module     - All 23 modules with controllers, services, DTOs"
    echo "  schema     - Complete Prisma schema (36 models, 7 enums)"
    echo "  auth       - JWT strategies, guards, decorators, roles"
    echo "  patterns   - Coding conventions, service patterns, error handling"
    echo "  integrations - eTelecom, Firebase, Redis, Email"
    echo "  setup      - Environment vars, Supabase config, scripts"
    echo "  orders     - Order lifecycle, statuses, refunds, returns"
    echo "  products   - Products, combos, categories, brands"
    echo "  inventory  - Sessions, transactions, lot tracking"
    echo "  vouchers   - Vouchers, rewards, spins, redemptions"
    echo "  customers  - Client management, sources, statuses, interactions"
    echo "  all        - Load everything (large output)"
    ;;
esac

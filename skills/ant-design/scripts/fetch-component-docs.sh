#!/usr/bin/env bash
# fetch-component-docs.sh
# Fetch live Ant Design documentation for a specific component or topic.
#
# Usage:
#   ./fetch-component-docs.sh <component-or-topic>
#
# Examples:
#   ./fetch-component-docs.sh select
#   ./fetch-component-docs.sh pro-table
#   ./fetch-component-docs.sh customize-theme
#
# The script prints the URL it fetched and a summary of what to look for.
# Claude should then call WebFetch on that URL with the question at hand.

set -euo pipefail

COMPONENT="${1:-}"

if [[ -z "$COMPONENT" ]]; then
  echo "Usage: $0 <component-or-topic>"
  echo ""
  echo "Component docs  →  https://ant.design/components/<name>"
  echo "React docs      →  https://ant.design/docs/react/<topic>"
  echo "Pro components  →  https://procomponents.ant.design/en-US/components/<name>"
  exit 1
fi

COMPONENT_LOWER="${COMPONENT,,}"

# --- Route table -----------------------------------------------------------
declare -A ROUTES=(
  # General
  ["button"]="https://ant.design/components/button"
  ["icon"]="https://ant.design/components/icon"
  ["typography"]="https://ant.design/components/typography"

  # Layout
  ["layout"]="https://ant.design/components/layout"
  ["grid"]="https://ant.design/components/grid"
  ["row"]="https://ant.design/components/grid"
  ["col"]="https://ant.design/components/grid"
  ["space"]="https://ant.design/components/space"
  ["flex"]="https://ant.design/components/flex"
  ["divider"]="https://ant.design/components/divider"
  ["splitter"]="https://ant.design/components/splitter"

  # Navigation
  ["menu"]="https://ant.design/components/menu"
  ["breadcrumb"]="https://ant.design/components/breadcrumb"
  ["dropdown"]="https://ant.design/components/dropdown"
  ["pagination"]="https://ant.design/components/pagination"
  ["steps"]="https://ant.design/components/steps"
  ["tabs"]="https://ant.design/components/tabs"
  ["anchor"]="https://ant.design/components/anchor"
  ["affix"]="https://ant.design/components/affix"
  ["float-button"]="https://ant.design/components/float-button"
  ["floatbutton"]="https://ant.design/components/float-button"
  ["back-top"]="https://ant.design/components/float-button"

  # Data Entry
  ["form"]="https://ant.design/components/form"
  ["input"]="https://ant.design/components/input"
  ["input-number"]="https://ant.design/components/input-number"
  ["inputnumber"]="https://ant.design/components/input-number"
  ["select"]="https://ant.design/components/select"
  ["checkbox"]="https://ant.design/components/checkbox"
  ["radio"]="https://ant.design/components/radio"
  ["switch"]="https://ant.design/components/switch"
  ["slider"]="https://ant.design/components/slider"
  ["date-picker"]="https://ant.design/components/date-picker"
  ["datepicker"]="https://ant.design/components/date-picker"
  ["time-picker"]="https://ant.design/components/time-picker"
  ["timepicker"]="https://ant.design/components/time-picker"
  ["upload"]="https://ant.design/components/upload"
  ["cascader"]="https://ant.design/components/cascader"
  ["transfer"]="https://ant.design/components/transfer"
  ["tree-select"]="https://ant.design/components/tree-select"
  ["treeselect"]="https://ant.design/components/tree-select"
  ["mentions"]="https://ant.design/components/mentions"
  ["rate"]="https://ant.design/components/rate"
  ["segmented"]="https://ant.design/components/segmented"
  ["color-picker"]="https://ant.design/components/color-picker"
  ["colorpicker"]="https://ant.design/components/color-picker"
  ["auto-complete"]="https://ant.design/components/auto-complete"
  ["autocomplete"]="https://ant.design/components/auto-complete"

  # Data Display
  ["table"]="https://ant.design/components/table"
  ["list"]="https://ant.design/components/list"
  ["card"]="https://ant.design/components/card"
  ["collapse"]="https://ant.design/components/collapse"
  ["carousel"]="https://ant.design/components/carousel"
  ["descriptions"]="https://ant.design/components/descriptions"
  ["empty"]="https://ant.design/components/empty"
  ["image"]="https://ant.design/components/image"
  ["avatar"]="https://ant.design/components/avatar"
  ["badge"]="https://ant.design/components/badge"
  ["tag"]="https://ant.design/components/tag"
  ["tooltip"]="https://ant.design/components/tooltip"
  ["popover"]="https://ant.design/components/popover"
  ["statistic"]="https://ant.design/components/statistic"
  ["tree"]="https://ant.design/components/tree"
  ["timeline"]="https://ant.design/components/timeline"
  ["calendar"]="https://ant.design/components/calendar"
  ["qrcode"]="https://ant.design/components/qr-code"
  ["qr-code"]="https://ant.design/components/qr-code"
  ["watermark"]="https://ant.design/components/watermark"

  # Feedback
  ["modal"]="https://ant.design/components/modal"
  ["drawer"]="https://ant.design/components/drawer"
  ["message"]="https://ant.design/components/message"
  ["notification"]="https://ant.design/components/notification"
  ["alert"]="https://ant.design/components/alert"
  ["spin"]="https://ant.design/components/spin"
  ["skeleton"]="https://ant.design/components/skeleton"
  ["progress"]="https://ant.design/components/progress"
  ["result"]="https://ant.design/components/result"
  ["popconfirm"]="https://ant.design/components/popconfirm"
  ["tour"]="https://ant.design/components/tour"

  # Utility
  ["app"]="https://ant.design/components/app"
  ["config-provider"]="https://ant.design/components/config-provider"
  ["configprovider"]="https://ant.design/components/config-provider"

  # React docs
  ["customize-theme"]="https://ant.design/docs/react/customize-theme"
  ["theme"]="https://ant.design/docs/react/customize-theme"
  ["compatible-style"]="https://ant.design/docs/react/compatible-style"
  ["use-with-vite"]="https://ant.design/docs/react/use-with-vite"
  ["use-with-next"]="https://ant.design/docs/react/use-with-next"
  ["migration-v5"]="https://ant.design/docs/react/migration-v5"
  ["migration-v6"]="https://ant.design/docs/react/migration-v6"
  ["server-side-rendering"]="https://ant.design/docs/react/server-side-rendering"
  ["ssr"]="https://ant.design/docs/react/server-side-rendering"
  ["faq"]="https://ant.design/docs/react/faq"

  # Pro Components
  ["pro-table"]="https://procomponents.ant.design/en-US/components/table"
  ["protable"]="https://procomponents.ant.design/en-US/components/table"
  ["pro-form"]="https://procomponents.ant.design/en-US/components/form"
  ["proform"]="https://procomponents.ant.design/en-US/components/form"
  ["pro-layout"]="https://procomponents.ant.design/en-US/components/layout"
  ["prolayout"]="https://procomponents.ant.design/en-US/components/layout"
  ["pro-list"]="https://procomponents.ant.design/en-US/components/list"
  ["prolist"]="https://procomponents.ant.design/en-US/components/list"
  ["pro-descriptions"]="https://procomponents.ant.design/en-US/components/descriptions"
)

URL="${ROUTES[$COMPONENT_LOWER]:-}"

if [[ -z "$URL" ]]; then
  # Fallback: try as a direct component slug
  URL="https://ant.design/components/${COMPONENT_LOWER}"
  echo "⚠️  No exact match for '${COMPONENT}'. Trying: $URL"
else
  echo "✓  Component: ${COMPONENT}"
  echo "   URL: $URL"
fi

echo ""
echo "─────────────────────────────────────────────"
echo "Fetch this URL with WebFetch and ask:"
echo "  'Extract all props, types, defaults,"
echo "   sub-components, and code examples'"
echo "─────────────────────────────────────────────"
echo "$URL"

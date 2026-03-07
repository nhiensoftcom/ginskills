---
name: icon-generator
description: |
  **SVG Icon Generator**: Generate beautiful, clean SVG icon components (.tsx) for React Native apps using react-native-svg.
  - MANDATORY TRIGGERS: generate icon, create icon, new icon, icon component, svg icon, make icon, add icon, design icon, draw icon, icon for, need icon, icon component, react native icon, mobile icon
  - Use this skill whenever the user wants to create a new SVG icon component for a React Native app. Also trigger when discussing icon design, icon style consistency, or generating multiple icons for a feature.
---

# SVG Icon Generator for React Native

Generate production-ready SVG icon components (`.tsx`) for React Native apps. Icons are hand-crafted as `react-native-svg` components — not image files.

## Output Directory

Before generating icons, **discover the project's icon directory** by searching for existing icon components:

1. Look for a directory containing `.tsx` files that import from `react-native-svg` (commonly `src/assets/icons/`, `src/icons/`, `src/components/icons/`, etc.)
2. Look for a barrel export file (`index.ts` or `index.tsx`) in that directory
3. If no existing icon directory is found, ask the user where icons should go

After creating the icon file, **always update the barrel export** if one exists.

## Discovering Project Conventions

Before generating the first icon in a project, **read 2-3 existing icon files** to detect:

- Which component pattern is used (see patterns below)
- Default color value (e.g. `#737373`, `#000`, `currentColor`)
- Default size (usually `24`)
- Stroke width (usually `1.5` or `2`)
- Whether the project uses a `size` prop convenience pattern
- Export style (default export, named export, or both)
- Whether there's a barrel `index.ts` file to update

Adapt all generated icons to match the project's existing conventions.

## Component Patterns

Three common patterns for react-native-svg icon components. Choose based on project conventions and complexity:

### Pattern A — Simple (most icons)

For single-color outline icons. Use `SvgProps` directly.

```tsx
import Svg, { Path, SvgProps } from "react-native-svg"

export const BellIcon = (props: SvgProps) => (
  <Svg width={24} height={24} viewBox="0 0 24 24" fill="none" {...props}>
    <Path
      d="M18 8A6 6 0 1 0 6 8c0 7-3 9-3 9h18s-3-2-3-9Z"
      stroke={props.color || "#737373"}
      strokeWidth={1.5}
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </Svg>
)

export default BellIcon
```

### Pattern B — With size prop

For icons that need a `size` convenience prop. Destructure and forward.

```tsx
import Svg, { Path, SvgProps } from "react-native-svg"

interface MyIconProps extends SvgProps {
  size?: number
}

const MyIcon = ({
  size = 24,
  width,
  height,
  color = "#FFFFFF",
  ...props
}: MyIconProps) => {
  const w = width ?? size
  const h = height ?? size

  return (
    <Svg width={w} height={h} viewBox="0 0 24 24" fill="none" {...props}>
      <Path d="..." fill={color} />
    </Svg>
  )
}

export default MyIcon
```

### Pattern C — Outlined + Filled variants

For icons that have both an outline and a filled version (e.g. tab bar icons). Export both as named exports from the same file.

```tsx
import Svg, { Path, SvgProps } from "react-native-svg"

export const OutlinedIcon = (props: SvgProps) => (
  <Svg height={24} width={24} fill="none" {...props}>
    <Path
      stroke={props.color || "#737373"}
      strokeWidth={1.5}
      d="..."
    />
  </Svg>
)

export const FilledIcon = (props: SvgProps) => (
  <Svg height={24} width={24} fill="none" {...props}>
    <Path
      fill={props.color || "#737373"}
      d="..."
      fillRule="evenodd"
      clipRule="evenodd"
    />
  </Svg>
)
```

### Available SVG elements

Import only what you need from `react-native-svg`:

| Element | Use for |
|---------|---------|
| `Path` | Most shapes — lines, curves, complex outlines |
| `Circle` | Dots, circular elements |
| `Rect` | Rectangles, rounded rectangles |
| `G` | Grouping elements |
| `Defs`, `LinearGradient`, `RadialGradient`, `Stop` | Gradient fills (complex icons only) |
| `ClipPath` | Clipping masks |

## SVG Design Rules

Follow these rules when crafting the `d` attribute and overall icon design:

### ViewBox & Grid

- **Always** use `viewBox="0 0 24 24"` unless the project uses a different standard (check existing icons)
- Default `width={24} height={24}` — consumers override via props
- Center the icon within the grid with ~1-2px visual padding

### Stroke Style (outline icons)

- `strokeWidth={1.5}` — common standard (adapt to project)
- `strokeLinecap="round"` — always round caps
- `strokeLinejoin="round"` — always round joins
- Default stroke color from `props.color` with a fallback (detect from existing icons)
- `fill="none"` on the `<Svg>` element

### Fill Style (solid icons)

- Use `fill={props.color || "..."}` on `<Path>` elements
- For complex filled shapes, use `fillRule="evenodd"` and `clipRule="evenodd"` to handle cutouts

### Path Quality

- **Minimize anchor points** — fewer points = cleaner curves. A good icon uses 5-15 path commands, not 50+.
- **Use relative commands** (`m`, `l`, `c`, `a`) where they reduce file size
- **Round coordinates** to 1-2 decimal places max — no `14.293847` nonsense
- **Prefer arcs (`A/a`)** for rounded corners and circles over many cubic beziers
- **Keep paths semantic** — split into multiple `<Path>` elements for distinct visual parts (e.g. separate the lid from the box)
- **No transforms on elements** — bake all transforms into the path data itself

### Visual Style

The icon set should follow a **Lucide-like** clean outline aesthetic:

- Uniform stroke weight
- Rounded caps and joins for friendly feel
- Geometric simplicity — reduce to essential form
- Optical balance — visually center, not mathematically center
- Consistent metaphors — follow existing icons in the project for similar concepts

### What NOT to do

- No inline `style` attributes — use SVG props only
- No `<text>` elements — icons should be purely graphical
- No hardcoded colors without the `props.color` fallback
- No `px`, `em`, or CSS units in SVG attributes — use plain numbers
- No `transform` attributes on child elements
- No `opacity` below 0.4 — it won't be visible on all backgrounds
- No overly complex paths (>2KB for a single path `d` string) — simplify the design

## Naming Convention

Follow the project's existing naming pattern. Common conventions:

| Rule | Example |
|------|---------|
| File name: PascalCase | `ShoppingBag.tsx` |
| Default export: PascalCase | `export default ShoppingBag` |
| Named export: PascalCase + `Icon` suffix | `export const ShoppingBagIcon = ...` |
| Outlined variant: `Outlined` prefix | `export const OutlinedShoppingBag = ...` |
| Filled variant: `Filled` prefix | `export const FilledShoppingBag = ...` |

## Barrel Export

After creating the icon, add the export to the project's icon barrel file (e.g. `index.ts`).

For Pattern A/B (default export + named export):
```ts
export { MyIconName } from "./MyIconName"
// or
export { default as MyIconNameIcon } from "./MyIconName"
```

For Pattern C (outlined + filled):
```ts
export { OutlinedMyIcon, FilledMyIcon } from "./MyIcon"
```

## Step-by-Step Process

When asked to generate an icon:

1. **Discover the project's icon directory** — Search for existing `.tsx` files importing from `react-native-svg`. Read 2-3 to learn the conventions.
2. **Clarify the concept** — Ask what the icon represents if not obvious. Check if a similar icon already exists.
3. **Choose the pattern** — Match the project's existing pattern. Default to Pattern A for simple outline icons, B if the project uses `size` props, C if both outline and filled variants are requested.
4. **Design the SVG paths** — Craft clean, minimal path data following the design rules above. Think of the icon in terms of simple geometric primitives.
5. **Write the component** — Create the `.tsx` file matching the project's conventions.
6. **Update barrel export** — Add the export to `index.ts` if one exists.
7. **Verify** — Confirm the icon renders by asking the user to check it in their app.

## Prompt Engineering for Beautiful Icons

When you need to design an icon from a concept, think through these steps:

### Decompose the concept into shapes

Break the icon into 2-4 simple geometric primitives:
- **Circle** → dots, heads, wheels, buttons
- **Rectangle** → screens, cards, documents, boxes
- **Triangle** → arrows, play buttons, mountains
- **Line** → dividers, stems, connections
- **Arc** → smiles, curves, partial circles

### Build the path step by step

1. Start with the largest/most distinctive shape
2. Add secondary details (e.g., handle on a bag, arrow on a share icon)
3. Remove any element that doesn't add meaning — minimalism is key
4. Test at 24×24: if a detail disappears at this size, remove it

### Common icon recipes

| Concept | Approach |
|---------|----------|
| Notification bell | Arc for bell body + small circle for clapper + curved line for top |
| Shopping bag | Rounded rect + two arc handles |
| Heart | Two cubic bezier curves meeting at a point |
| Star | 5-point star via alternating outer/inner radius points |
| Checkmark | Single path with two line segments at an angle |
| Arrow | Line + chevron head (or triangle for filled) |
| Gear/Settings | Circle + evenly spaced rectangular teeth |
| Lock | Rounded rect body + arc shackle |
| Eye | Two symmetrical arcs + circle pupil |
| Trash | Trapezoid body + horizontal lid line + vertical deletion lines |

### Fashion/clothing-specific icons

Patterns for clothing and fashion-related icons:
- **Hanger**: Arc hook on top + triangle body with slight shoulder curves
- **Shirt**: Rectangular body + notched collar + short sleeves using arcs
- **Dress**: Fitted top tapering to flared bottom via cubic beziers
- **Shoe**: Side profile — sole line + upper curve + heel
- **Closet/Wardrobe**: Rectangle with double doors (vertical line divider) + small circle handles

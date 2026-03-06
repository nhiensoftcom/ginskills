# Design System — Theme, Colors, Typography, Spacing

## Theme Usage

Always import from `@/shared/theme`:

```typescript
import { Theme, Spacing, scale, moderateScale, withFontWeight } from "@/shared/theme"

Theme.color.brand          // #EC4899
Theme.color.text           // #262626
Theme.typography.b1        // { fontSize: 16, lineHeight: 24, fontFamily: "Poppins-Regular" }
Spacing.lg                 // 16
```

## Color System

Sophisticated minimal with rose/blush brand accent. **Always use semantic tokens, never raw hex.**

### Brand Colors (use sparingly)

| Token | Value | Use |
|-------|-------|-----|
| `brand` | `#EC4899` | Primary brand (buttons, links) |
| `brandLight` | `#FFE4E9` | Light accent backgrounds |
| `brandSubtle` | `#FFF1F3` | Super light tint |
| `brandDark` | `#BE185D` | Dark brand emphasis |
| `brandText` | `#DB2777` | Brand-colored text |

### Backgrounds

| Token | Value | Use |
|-------|-------|-----|
| `background` | `#F6F6F9` | Screen background |
| `backgroundSubtle` | `#EDEDF0` | Secondary background |
| `backgroundElevated` | `#FFFFFF` | Cards, elevated surfaces |
| `backgroundInverse` | `#171717` | Dark backgrounds |

### Text

| Token | Value | Use |
|-------|-------|-----|
| `text` | `#262626` | Primary text |
| `textSecondary` | `#737373` | Secondary/muted |
| `textTertiary` | `#A3A3A3` | Placeholder, disabled |
| `textInverse` | `#FFFFFF` | On dark backgrounds |
| `textBrand` | `#DB2777` | Brand-colored text |

### Borders

| Token | Value | Use |
|-------|-------|-----|
| `border` | `#E5E5E5` | Default |
| `borderSubtle` | `#EDEDED` | Subtle |
| `borderStrong` | `#D4D4D4` | Emphasized |
| `borderBrand` | `#FDA4B8` | Brand accent |

### Interactive States

`interactive` (brand), `interactiveHover`, `interactiveActive`, `interactiveSubtle` (bg), `interactiveMuted` (selected bg)

### Status Colors

| Status | Main | Subtle | Muted | Text |
|--------|------|--------|-------|------|
| Success | `#22C55E` | `#F0FDF4` | `#DCFCE7` | `#15803D` |
| Warning | `#F59E0B` | `#FFFBEB` | `#FEF3C7` | `#B45309` |
| Error | `#EF4444` | `#FEF2F2` | `#FEE2E2` | `#B91C1C` |

### Special Tokens

`overlay` (rgba 0.5), `scrim` (rgba 0.6 for modals), `skeleton` (#E5E5E5), `disabled` (#D4D4D4), `focus` (#F87198), `ripple` (rgba 0.08 for Android)

## Typography

Font: **Poppins** (Google Fonts, weights 300-900)

### Variants

| Variant | Size | Height | Weight | Use |
|---------|------|--------|--------|-----|
| `xxl` | 72 | 80 | ExtraBold | Hero numbers |
| `h1` | 22 | 33 | Bold | Page titles |
| `h2` | 20 | 30 | Medium | Section headings |
| `h3` | 18 | 27 | Medium | Sub-headings |
| `b1` | 16 | 24 | Regular | Body text |
| `b2` | 14 | 21 | Regular | Small body |
| `b3` | 12 | 18 | Regular | Captions, labels |

### Usage

```typescript
import { Typography } from "@/shared/components"

<Typography variant="h1">Page Title</Typography>
<Typography variant="b2" color={Theme.color.textSecondary}>Subtitle</Typography>
```

### Font Weight Override

**Always use `withFontWeight()`** — never set fontWeight directly (breaks Android):

```typescript
import { withFontWeight } from "@/shared/theme"

// CORRECT: Maps to correct platform font family
const boldBody = withFontWeight(Theme.typography.b1, "700")

// WRONG: Breaks on Android (fontWeight without matching fontFamily)
const bad = { ...Theme.typography.b1, fontWeight: "700" }
```

### Platform Font Families

| Weight | iOS | Android |
|--------|-----|---------|
| 300 | `Poppins-Light` | `Poppins_300Light` |
| 400 | `Poppins-Regular` | `Poppins_400Regular` |
| 500 | `Poppins-Medium` | `Poppins_500Medium` |
| 600 | `Poppins-SemiBold` | `Poppins_600SemiBold` |
| 700 | `Poppins-Bold` | `Poppins_700Bold` |
| 800 | `Poppins-ExtraBold` | `Poppins_800ExtraBold` |

Typography component: `maxFontSizeMultiplier = 1.15` (prevents OS font scaling issues).

## Spacing System

4-point grid. **Always use `Spacing.*` tokens.**

### Component Spacing

| Token | Value | Use |
|-------|-------|-----|
| `xs` | 4 | Tight elements |
| `sm` | 8 | Compact layouts |
| `md` | 12 | Standard gaps |
| `lg` | 16 | Comfortable gaps |
| `xl` | 20 | Emphasis |
| `xxl` | 24 | Section spacing |
| `xxxl` | 32 | Large sections |

### Layout Spacing

| Token | Value | Use |
|-------|-------|-----|
| `screenHorizontal` | 16 | Screen padding L/R |
| `screenVertical` | 24 | Screen padding T/B |
| `sectionGap` | 24 | Between sections |
| `cardPadding` | 16 | Card internal padding |
| `cardInnerGap` | 12 | Gap inside cards |
| `cardRadius` | 16 | Standard card radius |
| `cardRadiusLarge` | 20 | Hero card radius |
| `touchTarget` | 44 | Min touch size (iOS HIG) |
| `listItemGap` | 12 | Between list items |

## Responsive Scaling

Baseline: 375x812 (iPhone 13/14)

```typescript
import { scale, verticalScale, moderateScale, DeviceSize } from "@/shared/theme"

scale(16)              // Linear horizontal scaling
verticalScale(24)      // Linear vertical scaling
moderateScale(16)      // Dampened (factor=0.5, recommended default)
moderateScale(16, 0.3) // Less aggressive

// Device breakpoints
DeviceSize.isSmall   // < 360px (older devices)
DeviceSize.isMedium  // 360-399px (mid-range)
DeviceSize.isLarge   // >= 400px (standard+)
```

Use `moderateScale` for text/padding, `scale` for widths/icons, raw values for tokens/borders.

## Shadow Pattern

```typescript
const styles = StyleSheet.create({
  card: {
    backgroundColor: Theme.color.backgroundElevated,
    borderRadius: Spacing.cardRadius,
    padding: Spacing.cardPadding,
    shadowColor: Theme.color.shadowColor,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.08,
    shadowRadius: 8,
    elevation: 3, // Android
  },
})
```

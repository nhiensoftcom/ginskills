# Ant Design — Theming & Design Tokens

## ConfigProvider theme prop

```tsx
import { ConfigProvider, theme } from 'antd';
import type { ThemeConfig } from 'antd';

<ConfigProvider
  theme={{
    token: { /* global design tokens */ },
    algorithm: theme.darkAlgorithm,            // derivation algorithm
    components: {                               // per-component overrides
      Button: { colorPrimary: '#ff0000', borderRadius: 4 },
    },
    cssVar: true,                              // enable CSS variables
    hashed: true,                              // hash-based class selectors (default)
    inherit: true,                             // inherit parent ConfigProvider (default)
    zeroRuntime: false,                        // v6+: pre-generate styles at build time
  }}
>
  <App />
</ConfigProvider>
```

> **Limitation:** `ConfigProvider` does NOT affect `message.xxx`, `Modal.xxx`, or `notification.xxx` static methods (they run outside React context). Use `App.useApp()` or `Modal.useModal()` instead.

---

## Three-Layer Token System

```
Seed Tokens → (algorithm) → Map Tokens → (specialization) → Alias Tokens
```

| Layer | Examples | When to change |
|-------|----------|----------------|
| **Seed Tokens** | `colorPrimary`, `borderRadius`, `fontSize` | Primary customization — algorithm derives the rest automatically |
| **Map Tokens** | `colorPrimaryHover`, `colorPrimaryBg`, `colorBgContainer` | Override specific derived values when algorithm result isn't right |
| **Alias Tokens** | `colorLink`, `colorTextHeading`, `colorTextBase` | Batch-control semantic colors across components |

---

## Color Seed Tokens

| Token | Default | Description |
|-------|---------|-------------|
| `colorPrimary` | `#1677ff` | Brand primary color — cascades to hover/active/bg/border variants |
| `colorSuccess` | `#52c41a` | Success state |
| `colorWarning` | `#faad14` | Warning state |
| `colorError` | `#ff4d4f` | Error / danger state |
| `colorInfo` | `#1677ff` | Info state |

## Derived Color Map Tokens (auto-calculated)

For each status color (primary/success/warning/error), these are auto-derived:
- `colorPrimaryBg` — lightest background tint
- `colorPrimaryBgHover` — hover background tint
- `colorPrimaryBorder` — border color
- `colorPrimaryBorderHover` — hover border
- `colorPrimaryHover` — hover state
- `colorPrimary` — base color
- `colorPrimaryActive` — pressed state
- `colorPrimaryTextHover` — text hover
- `colorPrimaryText` — text color
- `colorPrimaryTextActive` — text active

## Alias Tokens (Semantic Colors)

| Token | Description | Default |
|-------|-------------|---------|
| `colorLink` | Link text color | `colorPrimary` |
| `colorTextBase` | Base text | `#000` |
| `colorBgBase` | Base background | `#fff` |
| `colorBgContainer` | Container/card background | `#fff` |
| `colorBgLayout` | Page layout background | `#f5f5f5` |
| `colorBgElevated` | Elevated surface (modals, dropdowns) | `#fff` |
| `colorText` | Primary text | `rgba(0,0,0,0.88)` |
| `colorTextSecondary` | Secondary text | `rgba(0,0,0,0.45)` |
| `colorTextTertiary` | Tertiary text | `rgba(0,0,0,0.35)` |
| `colorTextDisabled` | Disabled text | `rgba(0,0,0,0.25)` |
| `colorBorder` | Default border | `#d9d9d9` |
| `colorBorderSecondary` | Secondary border | `#f0f0f0` |

---

## Sizing Tokens

| Token | Default | Description |
|-------|---------|-------------|
| `borderRadius` | `6` | Default radius (px) |
| `borderRadiusXS` | `2` | Extra small |
| `borderRadiusSM` | `4` | Small |
| `borderRadiusLG` | `8` | Large |
| `fontSize` | `14` | Base font (px) |
| `fontSizeSM` | `12` | Small |
| `fontSizeLG` | `16` | Large |
| `fontSizeXL` | `20` | Extra large |
| `controlHeight` | `32` | Input/control height (px) |
| `controlHeightSM` | `24` | Small control |
| `controlHeightLG` | `40` | Large control |
| `paddingXS` | `8` | Extra small padding |
| `paddingSM` | `12` | Small padding |
| `padding` | `16` | Default padding |
| `paddingLG` | `24` | Large padding |
| `paddingXL` | `32` | Extra large padding |

---

## Special Tokens

| Token | Default | Description |
|-------|---------|-------------|
| `wireframe` | `false` | Wireframe visual mode |
| `motion` | `true` | Enable animations |
| `motionDurationFast` | `0.1s` | Fast animation |
| `motionDurationMid` | `0.2s` | Medium animation |
| `motionDurationSlow` | `0.3s` | Slow animation |
| `fontFamily` | system fonts | Base font family |
| `fontWeightStrong` | `600` | Bold weight |
| `zIndexPopupBase` | `1000` | Popup base z-index |

---

## Algorithms

```tsx
import { theme } from 'antd';

// Single algorithm
<ConfigProvider theme={{ algorithm: theme.darkAlgorithm }}>
<ConfigProvider theme={{ algorithm: theme.compactAlgorithm }}>

// Combined (order matters)
<ConfigProvider theme={{ algorithm: [theme.darkAlgorithm, theme.compactAlgorithm] }}>

// Dynamic toggle
const [isDark, setIsDark] = useState(false);
<ConfigProvider theme={{ algorithm: isDark ? theme.darkAlgorithm : theme.defaultAlgorithm }}>
```

---

## Component Tokens

Each component has its own token scope:

```tsx
<ConfigProvider
  theme={{
    components: {
      Button: {
        colorPrimary: '#ff6900',
        borderRadius: 20,
        controlHeight: 40,
        algorithm: true,   // apply current theme algorithm to component
      },
      Input: {
        borderRadius: 4,
        colorBorder: '#91d5ff',
        hoverBorderColor: '#4096ff',
      },
      Menu: {
        itemBg: '#001529',
        itemColor: 'rgba(255,255,255,0.65)',
        itemSelectedBg: '#1677ff',
      },
      Table: {
        headerBg: '#f0f4f8',
        rowHoverBg: '#f5f5f5',
      },
    },
  }}
>
```

---

## Consuming Tokens

```tsx
// Inside React components
import { theme } from 'antd';
const { token } = theme.useToken();

<div style={{
  backgroundColor: token.colorBgContainer,
  color: token.colorText,
  padding: token.paddingLG,
  borderRadius: token.borderRadius,
  border: `1px solid ${token.colorBorderSecondary}`,
}} />

// Outside React (static / build tools)
const defaultToken = theme.getDesignToken();                              // default theme
const customToken = theme.getDesignToken({ token: { colorPrimary: '#f00' } }); // custom config
```

---

## Nested Themes

```tsx
<ConfigProvider theme={{ token: { colorPrimary: '#1677ff' } }}>
  {/* blue primary */}
  <Header />

  <ConfigProvider theme={{ token: { colorPrimary: '#52c41a' } }}>
    {/* green primary — inherits all other tokens from parent */}
    <Sidebar />
  </ConfigProvider>

  <ConfigProvider theme={{ inherit: false, token: { colorPrimary: '#722ed1' } }}>
    {/* inherit: false — fully isolated from parent */}
    <Widget />
  </ConfigProvider>
</ConfigProvider>
```

---

## CSS Variables Mode

```tsx
<ConfigProvider theme={{ cssVar: true, hashed: false }}>
  <App />
</ConfigProvider>
```

Generates `--ant-color-primary`, `--ant-border-radius`, etc. — enables runtime switching without React re-renders. You can also override them in plain CSS:

```css
:root { --ant-color-primary: #722ed1; }
```

---

## StyleProvider — Browser Compatibility

```tsx
import { StyleProvider, legacyLogicalPropertiesTransformer, px2remTransformer } from '@ant-design/cssinjs';

<StyleProvider
  hashPriority="high"                                    // disable :where() for old browsers
  transformers={[legacyLogicalPropertiesTransformer]}    // margin-inline-start → margin-left
  layer                                                  // enable @layer cascade ordering
>
  <App />
</StyleProvider>
```

### Tailwind CSS integration with @layer
```css
/* Tailwind v3 global.css */
@layer tailwind-base, antd;

/* Tailwind v4 global.css */
@layer theme, base, antd, components, utilities;
```

### px → rem transformer
```tsx
const px2rem = px2remTransformer({ rootValue: 16, precision: 5 });
<StyleProvider transformers={[px2rem]}><App /></StyleProvider>
```

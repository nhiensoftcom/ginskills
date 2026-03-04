# Ant Design — Installation & Framework Setup

## Installation

```bash
npm install antd
npm install @ant-design/icons   # icons are separate
```

Do NOT install `@types/antd` — TypeScript types are bundled in `antd` itself.

---

## Vite Setup

```bash
npm create vite@latest my-app --template react-ts
cd my-app
npm install antd @ant-design/icons
```

**`src/main.tsx`:**
```tsx
import React from 'react';
import ReactDOM from 'react-dom/client';
import 'antd/dist/reset.css';   // ONE-TIME global reset; import before your own CSS
import App from './App';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

**`vite.config.ts`** — no extra config needed for v5 (CSS-in-JS handles styles):
```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Only needed if using antd Less source (unusual in v5):
  // css: { preprocessorOptions: { less: { javascriptEnabled: true } } },
});
```

---

## Next.js App Router (13+ / 14+ / 15+)

```bash
npm install @ant-design/nextjs-registry
```

> Ensure `@ant-design/cssinjs` version matches the one inside `antd/node_modules`. Mismatched versions cause broken style extraction.

**`app/layout.tsx`:**
```tsx
import React from 'react';
import { AntdRegistry } from '@ant-design/nextjs-registry';
import { ConfigProvider } from 'antd';
import type { ThemeConfig } from 'antd';

const themeConfig: ThemeConfig = {
  token: { colorPrimary: '#1677ff' },
};

export default function RootLayout({ children }: React.PropsWithChildren) {
  return (
    <html lang="en">
      <body>
        <AntdRegistry>
          <ConfigProvider theme={themeConfig}>
            {children}
          </ConfigProvider>
        </AntdRegistry>
      </body>
    </html>
  );
}
```

**Client pages must be marked:**
```tsx
'use client';   // ALL antd components are client components
import { Button, Form } from 'antd';
```

**React 19 / Next.js 15 compatibility:**
```bash
npm install @ant-design/v5-patch-for-react-19
```
```tsx
import '@ant-design/v5-patch-for-react-19'; // import once at root layout
```

---

## Next.js Pages Router

```bash
npm install @ant-design/cssinjs
```

**`pages/_document.tsx`:**
```tsx
import React from 'react';
import { createCache, extractStyle, StyleProvider } from '@ant-design/cssinjs';
import Document, { Head, Html, Main, NextScript } from 'next/document';
import type { DocumentContext } from 'next/document';

const MyDocument = () => (
  <Html lang="en">
    <Head />
    <body>
      <Main />
      <NextScript />
    </body>
  </Html>
);

MyDocument.getInitialProps = async (ctx: DocumentContext) => {
  const cache = createCache();
  const originalRenderPage = ctx.renderPage;

  ctx.renderPage = () =>
    originalRenderPage({
      enhanceApp: (App) => (props) => (
        <StyleProvider cache={cache}>
          <App {...props} />
        </StyleProvider>
      ),
    });

  const initialProps = await Document.getInitialProps(ctx);
  const style = extractStyle(cache, true);

  return {
    ...initialProps,
    styles: (
      <>
        {initialProps.styles}
        <style dangerouslySetInnerHTML={{ __html: style }} />
      </>
    ),
  };
};

export default MyDocument;
```

**`pages/_app.tsx`:**
```tsx
import type { AppProps } from 'next/app';
import { ConfigProvider } from 'antd';

export default function MyApp({ Component, pageProps }: AppProps) {
  return (
    <ConfigProvider theme={{ token: { colorPrimary: '#1677ff' } }}>
      <Component {...pageProps} />
    </ConfigProvider>
  );
}
```

---

## v4 → v5 Migration

### Automated codemod first
```bash
npx -p @ant-design/codemod-v5 antd5-codemod src
```

### Key breaking changes

| What changed | v4 | v5 |
|---|---|---|
| Styling system | Less CSS | CSS-in-JS (auto) |
| CSS import | `antd/dist/antd.css` | `antd/dist/reset.css` |
| `babel-plugin-import` | required for tree shaking | **removed** — not needed or supported |
| Popup visibility | `visible` | `open` |
| Primary color | `#1890ff` | `#1677ff` |
| Default border radius | `2px` | `6px` |
| PageHeader | `antd` | `@ant-design/pro-components` |
| BackTop | `antd` | `FloatButton.BackTop` |
| `message.warn` | existed | removed → use `message.warning` |
| Form.create() | removed in v4 already | fully gone in v5 |

### Migration path
1. Upgrade to antd v4 latest → fix all deprecation warnings
2. Run codemod
3. `npm install antd@5`
4. Replace `antd/dist/antd.css` → `antd/dist/reset.css`
5. Remove `babel-plugin-import` from babel/vite config
6. Migrate Less variable overrides → `ConfigProvider theme.token`
7. Replace removed components from `@ant-design/compatible`

```bash
npm install @ant-design/compatible  # for PageHeader, Comment etc.
```

### `visible` → `open` migration
```tsx
// v4
<Modal visible={show} />
<Drawer visible={show} onVisibleChange={fn} />

// v5
<Modal open={show} />
<Drawer open={show} onOpenChange={fn} />
```

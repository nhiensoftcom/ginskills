# Ant Design — Feedback Components (Drawer, Message, Notification, Spin, Skeleton, App)

## Drawer

```typescript
import { Drawer } from 'antd';
import type { DrawerProps } from 'antd';
```

### DrawerProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `open` | `boolean` | `false` | Show/hide the drawer |
| `onClose` | `(e) => void` | — | Called when closing (mask click, ESC, close button) |
| `title` | `ReactNode` | — | Drawer header title |
| `placement` | `'top' \| 'right' \| 'bottom' \| 'left'` | `'right'` | Which side slides in from |
| `width` | `string \| number` | `378` | Width (left/right placement) |
| `height` | `string \| number` | `378` | Height (top/bottom placement) |
| `size` | `'default' \| 'large'` | `'default'` | Preset size |
| `extra` | `ReactNode` | — | Extra content in header (top right) |
| `footer` | `ReactNode` | — | Footer content |
| `mask` | `boolean` | `true` | Show backdrop |
| `maskClosable` | `boolean` | `true` | Close on mask click |
| `keyboard` | `boolean` | `true` | Close on ESC key |
| `destroyOnClose` | `boolean` | `false` | Unmount content when closed |
| `push` | `boolean \| { distance }` | `{ distance: 180 }` | Push sibling content |
| `zIndex` | `number` | `1000` | Z-index |
| `afterOpenChange` | `(open) => void` | — | After open/close animation |
| `getContainer` | `HTMLElement \| (() => HTMLElement) \| false` | `document.body` | Portal container |
| `styles` | `{ header?, body?, footer?, mask? }` | — | Semantic inline styles |
| `classNames` | `{ header?, body?, footer? }` | — | Semantic CSS classes |

### Patterns

```tsx
// Basic controlled drawer
const [open, setOpen] = useState(false);
<Button onClick={() => setOpen(true)}>Open</Button>
<Drawer title="Details" open={open} onClose={() => setOpen(false)} width={480}>
  <p>Content here</p>
</Drawer>

// Form in drawer with footer actions
<Drawer
  title="Add Record"
  open={open}
  onClose={() => setOpen(false)}
  footer={
    <Space>
      <Button onClick={() => setOpen(false)}>Cancel</Button>
      <Button type="primary" onClick={handleSubmit} loading={saving}>Submit</Button>
    </Space>
  }
  destroyOnClose
>
  <Form form={form} layout="vertical">
    <Form.Item name="name" label="Name" rules={[{ required: true }]}>
      <Input />
    </Form.Item>
  </Form>
</Drawer>

// Large drawer from left
<Drawer placement="left" size="large" title="Navigation" open={open} onClose={() => setOpen(false)}>
  <Menu mode="inline" items={menuItems} />
</Drawer>

// Without close button (custom close)
<Drawer
  title={<span>Title <CloseOutlined onClick={() => setOpen(false)} /></span>}
  closable={false}
  open={open}
  onClose={() => setOpen(false)}
>
  Content
</Drawer>
```

### Common Mistakes
- **Always update state in `onClose`** — `onClose={() => setOpen(false)}`; forgetting this means the drawer won't close
- **Use `destroyOnClose` for forms** — otherwise form state persists from previous open
- **Long content doesn't scroll by default** — add `styles={{ body: { overflowY: 'auto' } }}` if needed

---

## Message

Imperative API — brief top-of-page notifications that auto-dismiss.

```typescript
import { message } from 'antd';
```

### Methods

```typescript
message.success(content, duration?, onClose?)
message.error(content, duration?, onClose?)
message.info(content, duration?, onClose?)
message.warning(content, duration?, onClose?)
message.loading(content, duration?, onClose?)

// Config object form
message.success({ content: 'Done!', duration: 2, key: 'myMsg', onClose: () => {} })

// Destroy all
message.destroy()
message.destroy('specificKey')

// Global config
message.config({ maxCount: 3, duration: 2, top: 8 })
```

### Key/Update pattern

```typescript
// Show loading, then update to success/error
const key = 'uploading';
message.loading({ content: 'Uploading...', key, duration: 0 });

try {
  await uploadFile();
  message.success({ content: 'Done!', key, duration: 2 });
} catch {
  message.error({ content: 'Failed!', key, duration: 2 });
}
```

### Patterns

```tsx
// Inside click handlers
<Button onClick={() => message.success('Saved!')}>Save</Button>

// With duration 0 = never auto-close
message.loading({ content: 'Processing...', key, duration: 0 });

// Limit concurrent messages
message.config({ maxCount: 3 });

// Promise returned (resolves on close)
await message.success('Saved!');
```

### Common Mistakes
- **`message.xxx` is NOT affected by `ConfigProvider` theme/locale** — use `App.useApp()` for context-aware messages
- **Without `maxCount`, messages pile up** — always set `message.config({ maxCount: 3 })`
- **`key` update only works if the original message is still visible** — if it auto-closed, a new one appears

---

## Notification

Imperative API — corner notifications with title + description, longer content.

```typescript
import { notification } from 'antd';
```

### Methods

```typescript
notification.success({ message, description?, placement?, duration?, btn?, key?, onClose?, icon? })
notification.error({...})
notification.info({...})
notification.warning({...})
notification.open({...})

notification.destroy()        // close all
notification.close('key')     // close by key

// Global config
notification.config({
  placement: 'topRight',  // 'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight'
  duration: 4.5,
  maxCount: 5,
  top: 24, bottom: 24,
})
```

### Key properties

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `message` | `ReactNode` | — | Title (required) |
| `description` | `ReactNode` | — | Body text |
| `placement` | `'topLeft' \| 'topRight' \| 'bottomLeft' \| 'bottomRight'` | `'topRight'` | Position |
| `duration` | `number` | `4.5` | Auto-close seconds; `0` = never |
| `btn` | `ReactNode` | — | Action button |
| `key` | `string` | — | Unique ID for updates |
| `icon` | `ReactNode` | — | Custom icon |
| `onClose` | `() => void` | — | Close callback |
| `onClick` | `() => void` | — | Click callback |

### Patterns

```tsx
// Basic
notification.success({ message: 'Saved', description: 'Your changes were saved.' });

// With action button
notification.warning({
  message: 'Session expiring',
  description: 'Your session will expire in 5 minutes',
  duration: 0,
  key: 'session-warn',
  btn: (
    <Button size="small" type="primary"
      onClick={() => { extendSession(); notification.close('session-warn'); }}>
      Extend
    </Button>
  ),
});

// Update by key
notification.open({ message: 'Processing...', key: 'progress', duration: 0 });
// ... later:
notification.success({ message: 'Done!', key: 'progress' });

// Placement options
notification.info({ message: 'Info', placement: 'bottomRight' });
```

### Common Mistakes
- **`notification.xxx` is NOT affected by `ConfigProvider`** — use `App.useApp()` for context-aware notifications
- **Without `maxCount`, old notifications accumulate** — set `notification.config({ maxCount: 5 })`
- **`duration: 4.5` may be too short for long descriptions** — increase or set to `0` for persistent

---

## Spin

Loading spinner that can wrap content.

```typescript
import { Spin } from 'antd';
import type { SpinProps } from 'antd';
```

### SpinProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `spinning` | `boolean` | `true` | Show spinner |
| `tip` | `string \| ReactNode` | — | Loading text below spinner |
| `size` | `'small' \| 'default' \| 'large'` | `'default'` | Spinner size |
| `delay` | `number` | `0` | Delay (ms) before showing |
| `indicator` | `ReactNode` | — | Custom spinner element |
| `fullscreen` | `boolean` | `false` | Full-page overlay |
| `children` | `ReactNode` | — | Content to overlay when spinning |
| `wrapperClassName` | `string` | — | Class for wrapper div |

### Patterns

```tsx
// Standalone spinner
<Spin />
<Spin size="large" tip="Loading..." />

// Content overlay
<Spin spinning={isLoading}>
  <Table dataSource={data} columns={columns} />
</Spin>

// Custom indicator
<Spin indicator={<LoadingOutlined style={{ fontSize: 24 }} spin />} />

// Delayed (avoid flash for fast operations)
<Spin spinning={loading} delay={500}>
  <Content />
</Spin>

// Fullscreen
<Spin fullscreen spinning={processing} tip="Please wait..." />

// Conditional (avoid empty wrapper)
{isLoading ? <Spin /> : <Content />}
```

### Common Mistakes
- **`Spin` wrapping children blocks all interaction** while `spinning={true}` — intentional but verify UX
- **Custom icon needs `spin` CSS** — use `<LoadingOutlined spin />` from `@ant-design/icons`
- **`delay` causes flicker** on variable-speed operations — use judiciously (500ms is safe)

---

## Skeleton

Placeholder UI that mimics content structure during loading.

```typescript
import { Skeleton } from 'antd';
import type { SkeletonProps } from 'antd';
```

### SkeletonProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `loading` | `boolean` | `true` | Show skeleton vs content |
| `active` | `boolean` | `false` | Shimmer animation |
| `avatar` | `boolean \| SkeletonAvatarProps` | `false` | Show avatar placeholder |
| `title` | `boolean \| { width }` | `true` | Show title bar |
| `paragraph` | `boolean \| { rows, width }` | `true` | Show text lines |
| `round` | `boolean` | `false` | Rounded corners on all bars |

### Sub-components

```typescript
// Standalone placeholders
<Skeleton.Avatar active size="large" shape="circle" />
<Skeleton.Button active size="large" block />
<Skeleton.Input active size="default" block />
<Skeleton.Image active />

// Avatar shapes: 'circle' | 'square'
// Button shapes: 'default' | 'circle' | 'round'
// Sizes: 'small' | 'default' | 'large' | number
```

### Patterns

```tsx
// Standard loading skeleton
<Skeleton loading={isLoading} active avatar paragraph={{ rows: 4 }}>
  <ActualContent />
</Skeleton>

// Profile card skeleton
<Card>
  <Skeleton active avatar={{ size: 'large', shape: 'circle' }} paragraph={{ rows: 2 }} />
</Card>

// List skeleton
{isLoading
  ? Array.from({ length: 5 }).map((_, i) => (
      <List.Item key={i}>
        <Skeleton active avatar loading />
      </List.Item>
    ))
  : <List dataSource={data} renderItem={...} />
}

// Mixed sub-components (custom layout)
<Space direction="vertical" style={{ width: '100%' }}>
  <Skeleton.Avatar active size="large" />
  <Skeleton.Button active block size="large" />
  <Skeleton.Input active block />
</Space>
```

### Common Mistakes
- **`active` is `false` by default** — add `active` for shimmer animation
- **Match skeleton dimensions to content** — size mismatch causes layout shift when content loads
- **Paragraph rows default is 3** — set `paragraph={{ rows: 2 }}` to match shorter content

---

## App

Context provider that makes `message`, `notification`, and `modal` context-aware (respects `ConfigProvider` theme and locale).

```typescript
import { App } from 'antd';
// Must wrap the root of your app (or the subtree that needs context-aware imperative APIs)
```

### Why use App?

Static methods (`message.xxx`, `notification.xxx`, `Modal.confirm`) do NOT inherit `ConfigProvider` theme/locale. Wrapping with `App` and using `App.useApp()` inside components fixes this.

### Setup

```tsx
// Root layout — wrap once
<ConfigProvider theme={myTheme}>
  <App message={{ maxCount: 3 }} notification={{ placement: 'bottomRight' }}>
    <Router>
      <Routes />
    </Router>
  </App>
</ConfigProvider>
```

### App Props

| Prop | Type | Description |
|------|------|-------------|
| `message` | `MessageConfig` | Message instance config (maxCount, duration, etc.) |
| `notification` | `NotificationConfig` | Notification instance config |
| `modal` | `ModalConfig` | Modal instance config |

### useApp() hook

```typescript
import { App } from 'antd';

const MyComponent = () => {
  const { message, notification, modal } = App.useApp();
  // These are context-aware — they respect ConfigProvider theme/locale

  const handleSave = async () => {
    try {
      await saveData();
      message.success('Saved!');
    } catch {
      message.error('Failed!');
    }
  };

  const handleDelete = () => {
    modal.confirm({
      title: 'Delete item?',
      content: 'This action cannot be undone.',
      okText: 'Delete',
      okType: 'danger',
      onOk: async () => {
        await deleteItem();
        notification.success({ message: 'Deleted', description: 'Item removed.' });
      },
    });
  };

  return (
    <>
      <Button onClick={handleSave}>Save</Button>
      <Button danger onClick={handleDelete}>Delete</Button>
    </>
  );
};
```

### Common Mistakes
- **`App.useApp()` must be called inside an `<App>` wrapper** — calling outside throws an error
- **Only one `<App>` at root level** — multiple `App` wrappers can cause unexpected behavior
- **For static method fallback** — if `App` setup is too complex, the static methods still work but won't respect theme

---

## Comparison: When to Use What

| Feedback Type | Use | Duration | Position |
|---------------|-----|----------|----------|
| Success/error on user action | `message.success/error` | 3s auto | Top center |
| Important status update | `notification.success/info` | 4.5s auto | Corner |
| Warning needing action | `notification.warning + btn` | `duration: 0` | Corner |
| Async loading overlay | `<Spin spinning={loading}>` | — | Over content |
| Page loading placeholder | `<Skeleton loading={loading}>` | — | In place |
| Side panel form/content | `<Drawer>` | — | Side slide |
| Context-aware messages | `App.useApp()` | — | Respects theme |

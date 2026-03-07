---
name: ant-design
description: |
  **Ant Design (antd) Expert**: Production patterns for building React UIs with Ant Design v5/v6 — components, theming, Form, Table, Modal, layout, icons, TypeScript, Next.js/Vite setup, and best practices.
  - MANDATORY TRIGGERS: ant design, antd, ant-design, <Button, <Form, <Table, <Modal, <Select, <Input, <DatePicker, <ConfigProvider, antd theme, antd dark mode, antd form, antd table, antd modal, antd layout, antd component, antd v5, antd v6, ant design component, design token, colorPrimary, borderRadius, darkAlgorithm, compactAlgorithm, Form.useForm, Form.Item, TableColumnsType, Modal.confirm, Modal.useModal, useToken, ConfigProvider theme, antd migration, antd vite, antd next.js, antd nextjs, antd ssr, antd import, antd icon, @ant-design/icons
  - Use this skill when building, reviewing, or debugging React code that imports from `antd` or `@ant-design/icons`, or when setting up Ant Design in a project.
---

# Ant Design (antd) — Expert Guide

## Quick Start

```bash
npm install antd @ant-design/icons
```

```tsx
// src/main.tsx — import once at root
import 'antd/dist/reset.css';

// Components auto tree-shake — no plugin needed in v5
import { Button, Form, Table, Modal, Select, Input, DatePicker } from 'antd';
import { SearchOutlined, PlusOutlined } from '@ant-design/icons';
```

---

## Key Principles

1. **No `@types/antd`** — TypeScript types are bundled in `antd` itself
2. **No `babel-plugin-import`** — v5 CSS-in-JS auto loads styles on demand
3. **`antd/dist/reset.css`** — import once at root (replaces `antd/dist/antd.css`)
4. **`visible` → `open`** — all popups/overlays use `open` prop in v5+
5. **`ConfigProvider` does NOT affect** `message.xxx` / `Modal.xxx` / `notification.xxx` static methods — use `App.useApp()` or `Modal.useModal()` instead

---

## Theme Customization

```tsx
import { ConfigProvider, theme } from 'antd';
import type { ThemeConfig } from 'antd';

const myTheme: ThemeConfig = {
  token: {
    colorPrimary: '#1677ff',   // brand color (cascades to all primary variants)
    borderRadius: 6,
    fontSize: 14,
    fontFamily: 'Inter, sans-serif',
  },
  algorithm: theme.darkAlgorithm,        // light | dark | compact | [dark, compact]
  components: {
    Button: { borderRadius: 20 },        // per-component override
    Table: { headerBg: '#f0f4f8' },
  },
  cssVar: true,                          // enables CSS variables for runtime theming
};

<ConfigProvider theme={myTheme}>
  <App />
</ConfigProvider>
```

### Token layers (3-tier system)
| Layer | Example | Use |
|-------|---------|-----|
| Seed Token | `colorPrimary`, `borderRadius` | Set root values; algorithm derives the rest |
| Map Token | `colorPrimaryHover`, `colorPrimaryBg` | Auto-derived; override cautiously |
| Alias Token | `colorLink`, `colorTextHeading` | Semantic batch-controls across components |

### Consume tokens inside components
```tsx
import { theme } from 'antd';
const { token } = theme.useToken();
// token.colorPrimary, token.borderRadius, token.paddingLG, ...

// Outside React (build time / utilities)
const t = theme.getDesignToken({ token: { colorPrimary: '#f00' } });
```

### Dynamic dark/light toggle
```tsx
const [isDark, setIsDark] = useState(false);
<ConfigProvider theme={{ algorithm: isDark ? theme.darkAlgorithm : theme.defaultAlgorithm }}>
```

---

## Form — Core Patterns

```tsx
import { Form, Input, Button, Select, Checkbox } from 'antd';

const [form] = Form.useForm<MyValues>();

<Form form={form} layout="vertical" onFinish={onFinish} scrollToFirstError>
  <Form.Item name="email" label="Email"
    rules={[{ required: true }, { type: 'email', message: 'Invalid email' }]}>
    <Input />
  </Form.Item>

  <Form.Item name="role" label="Role" rules={[{ required: true }]}>
    <Select options={[{ value: 'admin', label: 'Admin' }]} />
  </Form.Item>

  {/* Boolean controls need valuePropName="checked" */}
  <Form.Item name="active" valuePropName="checked">
    <Checkbox>Active</Checkbox>
  </Form.Item>

  <Button type="primary" htmlType="submit">Submit</Button>
</Form>
```

### FormInstance methods
```tsx
form.setFieldValue('email', 'test@test.com');   // single field
form.setFieldsValue({ email: 'x', role: 'y' }); // multiple
form.validateFields();                           // returns Promise<Values>
form.resetFields();
form.getFieldValue('email');

// Reactive watch (use instead of getFieldsValue in render)
const email = Form.useWatch('email', form);
```

> **Read `docs/key-components.md`** for full Form API, validation rules, Form.List dynamic fields, common mistakes.

---

## Table — Core Pattern

```tsx
import type { TableColumnsType } from 'antd';
import { Table, Tag, Button } from 'antd';

const columns: TableColumnsType<User> = [
  {
    title: 'Name', dataIndex: 'name',
    sorter: (a, b) => a.name.localeCompare(b.name),
  },
  {
    title: 'Status', dataIndex: 'status',
    filters: [{ text: 'Active', value: 'active' }],
    onFilter: (value, record) => record.status === value,
    render: (status) => <Tag color={status === 'active' ? 'green' : 'red'}>{status}</Tag>,
  },
  {
    title: 'Actions', key: 'actions', fixed: 'right', width: 100,
    render: (_, record) => <Button onClick={() => edit(record)}>Edit</Button>,
  },
];

<Table<User>
  dataSource={data}
  columns={columns}
  rowKey="id"
  pagination={{ pageSize: 20, showSizeChanger: true }}
  rowSelection={{ type: 'checkbox', onChange: onSelectChange }}
  scroll={{ x: 1000 }}
  onChange={(pagination, filters, sorter) => fetchData({ ...pagination, filters, sorter })}
/>
```

> **Read `docs/key-components.md`** for full column API, server-side sorting/filtering, virtual scrolling, expandable rows.

---

## Modal — Core Patterns

```tsx
// Controlled component
<Modal open={visible} title="Edit" onOk={handleOk} onCancel={close}
  confirmLoading={saving} destroyOnHidden width={600}>
  <Form form={form}>...</Form>
</Modal>

// Imperative — use useModal for context access (NOT Modal.confirm directly)
const [modal, contextHolder] = Modal.useModal();
// render {contextHolder} in the JSX tree
modal.confirm({ title: 'Delete?', onOk: async () => { await deleteItem(); } });
modal.info({ ... }); modal.success({ ... }); modal.error({ ... });

// Static (NO context — theme/locale won't apply)
Modal.confirm({ title: 'Are you sure?', onOk: () => {} });
```

---

## Button — Key Variants

```tsx
<Button type="primary">Primary</Button>
<Button type="primary" danger>Delete</Button>
<Button type="primary" loading={saving}>Save</Button>
<Button type="primary" icon={<PlusOutlined />}>Add</Button>
<Button type="primary" htmlType="submit" block>Submit Form</Button>

{/* v5.21+ color+variant system */}
<Button color="primary" variant="outlined">Ghost-style</Button>
<Button color="danger" variant="filled">Soft Danger</Button>
<Button color="green" variant="solid">Green Solid</Button>
```

---

## Layout

```tsx
import { Layout, Menu } from 'antd';
const { Header, Content, Sider, Footer } = Layout;

<Layout style={{ minHeight: '100vh' }}>
  <Sider collapsible>
    <Menu theme="dark" mode="inline" items={menuItems} />
  </Sider>
  <Layout>
    <Header style={{ background: '#fff', padding: 0 }} />
    <Content style={{ margin: '24px 16px', padding: 24 }}>
      {children}
    </Content>
    <Footer>Footer</Footer>
  </Layout>
</Layout>
```

---

## Feedback Components

```tsx
// Transient global messages (top of page)
import { message, notification } from 'antd';
message.success('Saved!');
message.error('Failed.');
message.loading('Processing...', 2.5);

// Persistent notifications (corner)
notification.success({ message: 'Done', description: 'Your record was saved.' });

// Use App.useApp() to get context-aware versions
import { App } from 'antd';
const { message, modal, notification } = App.useApp();
// Wrap root with <App><Root /></App>
```

---

## Common Components Quick Reference

| Component | Import | Key props |
|-----------|--------|-----------|
| Input | `antd` | `value`, `onChange`, `allowClear`, `prefix`, `suffix`, `addonAfter` |
| Input.TextArea | `antd` | `rows`, `autoSize`, `showCount`, `maxLength` |
| Input.Password | `antd` | `visibilityToggle` |
| Select | `antd` | `mode` (multiple/tags), `options`, `showSearch`, `allowClear`, `loading`, `fieldNames` |
| DatePicker | `antd` | `picker`, `showTime`, `format`, `disabledDate`, `onChange` |
| Checkbox | `antd` | `checked`, `onChange`; `Checkbox.Group` for grouped |
| Radio | `antd` | `value`; `Radio.Group`, `Radio.Button` |
| Switch | `antd` | `checked`, `onChange`, `checkedChildren` |
| Upload | `antd` | `action`, `accept`, `multiple`, `beforeUpload`, `fileList`, `listType` |
| Spin | `antd` | `spinning`, `tip`, wraps content |
| Alert | `antd` | `type` (success/info/warning/error), `message`, `description`, `closable` |
| Tag | `antd` | `color`, `closable`, `onClose` |
| Badge | `antd` | `count`, `dot`, `status`, `offset` |
| Tooltip | `antd` | `title`, `placement`, wraps target |
| Popconfirm | `antd` | `title`, `onConfirm`, `onCancel`, `okText`, `cancelText` |
| Drawer | `antd` | `open`, `onClose`, `title`, `placement`, `width` |
| Card | `antd` | `title`, `extra`, `loading`, `actions`, `hoverable` |
| Avatar | `antd` | `src`, `icon`, `size`, `shape`; `Avatar.Group` |
| Tabs | `antd` | `items`, `activeKey`, `onChange`, `type`, `tabPosition` |

---

## Icons

```bash
npm install @ant-design/icons
```

```tsx
import { SearchOutlined, HeartFilled, SmileTwoTone } from '@ant-design/icons';
// Naming: <Name>Outlined | <Name>Filled | <Name>TwoTone
// TwoTone supports twoToneColor prop

<SearchOutlined style={{ fontSize: 20, color: '#1677ff' }} />
```

---

## Loading Docs On Demand

**Do NOT load all docs at once.** Use the routing guide below to load only what is needed.

### Docs Routing Guide

| Topic / Component | Load This File |
|-------------------|---------------|
| Vite / Next.js setup, v4→v5 migration | `docs/setup.md` |
| Theme tokens, dark mode, ConfigProvider, CSS vars | `docs/theme.md` |
| Form, Table, Modal, Button (full API) | `docs/key-components.md` |
| Menu, Tabs, Layout, Grid | `docs/navigation.md` |
| Select, Upload, DatePicker, Input (full API) | `docs/data-entry.md` |
| Typography, Card, List, Descriptions, Space, Flex | `docs/display.md` |
| Drawer, Message, Notification, Spin, Skeleton, App | `docs/feedback.md` |
| ProTable, ProForm, ProLayout | `docs/pro-components.md` |
| All 60+ components — quick reference | `docs/components.md` |

### Fetching Live Docs For Any Component

Use the fetch script to get the latest URL for any component, then call `WebFetch` on it:

```bash
# Run to get the URL for a component
bash ginstudio-skills/skills/ant-design/scripts/fetch-component-docs.sh <component-name>
# Examples:
bash ginstudio-skills/skills/ant-design/scripts/fetch-component-docs.sh select
bash ginstudio-skills/skills/ant-design/scripts/fetch-component-docs.sh pro-table
bash ginstudio-skills/skills/ant-design/scripts/fetch-component-docs.sh customize-theme
```

Then fetch the returned URL with `WebFetch` using the prompt:
> "Extract all props, types, defaults, sub-components, and code examples"

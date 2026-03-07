# Ant Design — Navigation Components (Menu, Tabs, Layout, Grid)

## Menu

```typescript
import { Menu } from 'antd';
import type { MenuProps } from 'antd';
type MenuItem = Required<MenuProps>['items'][number];
```

### MenuProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `items` | `ItemType[]` | — | Menu items array (preferred over JSX children) |
| `mode` | `'vertical' \| 'horizontal' \| 'inline'` | `'vertical'` | Layout orientation |
| `theme` | `'light' \| 'dark'` | `'light'` | Color scheme |
| `selectedKeys` | `string[]` | — | Controlled selected keys |
| `defaultSelectedKeys` | `string[]` | — | Initial selected keys (uncontrolled) |
| `openKeys` | `string[]` | — | Controlled open submenu keys |
| `defaultOpenKeys` | `string[]` | — | Initial open submenu keys (uncontrolled) |
| `inlineCollapsed` | `boolean` | — | Collapse/expand inline menu |
| `inlineIndent` | `number` | `24` | Pixel indent per nesting level |
| `multiple` | `boolean` | `false` | Allow multi-selection |
| `triggerSubMenuAction` | `'hover' \| 'click'` | `'hover'` | What opens submenus |
| `onClick` | `({ key, keyPath, domEvent }) => void` | — | Item click handler |
| `onSelect` | `({ key, keyPath, selectedKeys }) => void` | — | Item select handler |
| `onOpenChange` | `(openKeys: string[]) => void` | — | Submenu open state change |

### ItemType Variants

```typescript
// Menu item
type MenuItemType = {
  key: string;
  label: ReactNode;
  icon?: ReactNode;
  disabled?: boolean;
  danger?: boolean;        // red danger styling
  title?: string;          // tooltip when collapsed
};

// Submenu
type SubMenuType = {
  key: string;
  label: ReactNode;
  icon?: ReactNode;
  children: ItemType[];
  popupClassName?: string;
};

// Group
type MenuItemGroupType = { type: 'group'; label?: ReactNode; children?: MenuItemType[] };

// Divider
type MenuDividerType = { type: 'divider'; dashed?: boolean };
```

### Patterns

```tsx
// Sidebar (inline collapsible)
const items: MenuItem[] = [
  { key: '1', icon: <PieChartOutlined />, label: 'Dashboard' },
  { key: '2', icon: <MailOutlined />, label: 'Inbox' },
  {
    key: 'sub1', label: 'Settings', icon: <SettingOutlined />,
    children: [
      { key: '5', label: 'Profile' },
      { key: '6', label: 'Security' },
    ],
  },
  { type: 'divider' },
  { type: 'group', label: 'Admin', children: [{ key: 'g1', label: 'Users', danger: true }] },
];

<Menu mode="inline" theme="dark" inlineCollapsed={collapsed}
  selectedKeys={[current]} onClick={({ key }) => setCurrent(key)} items={items} />

// Horizontal nav
<Menu mode="horizontal" items={items} style={{ flex: 1, minWidth: 0 }} />
```

### Common Mistakes
- **Use `items` prop**, not JSX children (`<Menu.Item>`) — deprecated
- **`openKeys` (controlled) requires `onOpenChange`** — or submenus never open; use `defaultOpenKeys` for uncontrolled
- **`key` must be unique** across the entire items tree
- **`inlineCollapsed` only works with `mode="inline"`**
- **Horizontal menu needs `style={{ flex: 1, minWidth: 0 }}`** to handle overflow correctly

---

## Tabs

```typescript
import { Tabs } from 'antd';
import type { TabsProps } from 'antd';
```

### TabsProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `items` | `TabItemType[]` | `[]` | Tab definitions |
| `activeKey` | `string` | — | Controlled active key |
| `defaultActiveKey` | `string` | First key | Initial active key (uncontrolled) |
| `type` | `'line' \| 'card' \| 'editable-card'` | `'line'` | Visual style |
| `tabPlacement` | `'top' \| 'end' \| 'bottom' \| 'start'` | `'top'` | Tab bar position |
| `size` | `'large' \| 'middle' \| 'small'` | `'middle'` | Tab size |
| `centered` | `boolean` | `false` | Center the tab bar |
| `destroyOnHidden` | `boolean` | `false` | Unmount inactive panes |
| `animated` | `boolean \| { inkBar, tabPane }` | `{ inkBar: true, tabPane: false }` | Animation config |
| `tabBarExtraContent` | `ReactNode \| { left?, right? }` | — | Extra content in tab bar |
| `onChange` | `(activeKey: string) => void` | — | Active tab change |
| `onEdit` | `(targetKey, action: 'add' \| 'remove') => void` | — | Add/remove (editable-card only) |

### TabItemType

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `key` | `string` | — | Unique identifier |
| `label` | `ReactNode` | — | Tab header |
| `icon` | `ReactNode` | — | Icon in header |
| `children` | `ReactNode` | — | Tab pane content |
| `disabled` | `boolean` | `false` | Disable the tab |
| `closable` | `boolean` | `true` | Show close button (editable-card) |
| `destroyOnHidden` | `boolean` | `false` | Per-tab unmount override |
| `forceRender` | `boolean` | `false` | Render before first activation |

### Patterns

```tsx
// Basic
const items: TabsProps['items'] = [
  { key: '1', label: 'Tab 1', icon: <AppleOutlined />, children: <Content /> },
  { key: '2', label: 'Tab 2', children: <Content />, disabled: true },
];
<Tabs defaultActiveKey="1" items={items} onChange={setActiveKey} />

// Editable-card (add/remove tabs)
const onEdit = (targetKey: string, action: 'add' | 'remove') => {
  if (action === 'add') addTab();
  else setItems(items.filter(i => i.key !== targetKey));
};
<Tabs type="editable-card" activeKey={activeKey} onChange={setActiveKey}
  onEdit={onEdit} items={items} />

// Side placement + extra content
<Tabs tabPlacement="start" items={items}
  tabBarExtraContent={{ right: <Button>Action</Button> }} />
```

### Common Mistakes
- **`tabPosition` is deprecated** — use `tabPlacement`; values changed: `'left'/'right'` → `'start'/'end'`
- **`destroyInactiveTabPane` is deprecated** — use `destroyOnHidden`
- **`onEdit` only fires for `type="editable-card"`**
- **Tab `key` must be a string**, even for numeric IDs

---

## Layout

```typescript
import { Layout } from 'antd';
const { Header, Sider, Content, Footer } = Layout;
```

### Layout.Sider Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `collapsed` | `boolean` | — | Controlled collapsed state |
| `collapsible` | `boolean` | `false` | Show collapse trigger |
| `defaultCollapsed` | `boolean` | `false` | Initial state (uncontrolled) |
| `collapsedWidth` | `number \| string` | `80` | Width when collapsed; `0` = fully hidden |
| `width` | `number \| string` | `200` | Width when expanded |
| `breakpoint` | `'xs' \| 'sm' \| 'md' \| 'lg' \| 'xl' \| 'xxl'` | — | Responsive auto-collapse |
| `theme` | `'light' \| 'dark'` | `'dark'` | Sider color scheme |
| `trigger` | `ReactNode` | — | Custom trigger; `null` = hide trigger |
| `reverseArrow` | `boolean` | `false` | Flip arrow (for right-side siders) |
| `onCollapse` | `(collapsed, type) => void` | — | Collapse state change |
| `onBreakpoint` | `(broken: boolean) => void` | — | Responsive breakpoint hit |

### Patterns

```tsx
// Classic admin dashboard
<Layout style={{ minHeight: '100vh' }}>
  <Sider collapsible collapsed={collapsed} onCollapse={setCollapsed}>
    <Menu theme="dark" mode="inline" items={menuItems} />
  </Sider>
  <Layout>
    <Header style={{ padding: 0, background: colorBgContainer }} />
    <Content style={{ margin: 16 }}>
      <div style={{ padding: 24, background: colorBgContainer, borderRadius: borderRadiusLG }}>
        Page Content
      </div>
    </Content>
    <Footer style={{ textAlign: 'center' }}>App ©{new Date().getFullYear()}</Footer>
  </Layout>
</Layout>

// Custom trigger in header (not Sider)
<Sider trigger={null} collapsible collapsed={collapsed}>...</Sider>
<Header>
  <Button type="text" icon={collapsed ? <MenuUnfoldOutlined /> : <MenuFoldOutlined />}
    onClick={() => setCollapsed(!collapsed)} />
</Header>

// Responsive auto-collapse at lg
<Sider breakpoint="lg" collapsedWidth="0" onBreakpoint={console.log}>
  <Menu theme="dark" mode="inline" items={menuItems} />
</Sider>

// Sticky sider (scrollable content)
<Layout hasSider>
  <Sider style={{ overflow: 'auto', height: '100vh', position: 'sticky', top: 0, insetInlineStart: 0 }}>
    ...
  </Sider>
  <Layout>...</Layout>
</Layout>
```

### Common Mistakes
- **Add `hasSider` for SSR** — prevents layout flash during hydration
- **`trigger={null}` requires your own toggle mechanism**
- **Sider `theme` and Menu `theme` must match** or background colors conflict
- **`collapsedWidth={0}` shows a floating trigger button** — style it with `zeroWidthTriggerStyle`
- **Outer Layout needs `minHeight: '100vh'`** for full-page dashboard backgrounds

---

## Grid (Row / Col)

```typescript
import { Row, Col, Grid } from 'antd';
const { useBreakpoint } = Grid;
```

24-column Flex-based layout system.

### Breakpoints

| Name | Min Width |
|------|-----------|
| `xs` | < 576px |
| `sm` | ≥ 576px |
| `md` | ≥ 768px |
| `lg` | ≥ 992px |
| `xl` | ≥ 1200px |
| `xxl` | ≥ 1600px |

### Row Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `gutter` | `number \| [h, v] \| { xs, sm, md, lg, xl, xxl }` | `0` | Column spacing |
| `justify` | `'start' \| 'end' \| 'center' \| 'space-around' \| 'space-between' \| 'space-evenly'` | `'start'` | Horizontal distribution |
| `align` | `'top' \| 'middle' \| 'bottom' \| 'stretch'` | `'top'` | Vertical alignment |
| `wrap` | `boolean` | `true` | Whether columns wrap |

### Col Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `span` | `number` | — | Columns to span (0–24); `0` = hidden |
| `offset` | `number` | `0` | Left offset columns |
| `order` | `number` | `0` | Flex order |
| `push` / `pull` | `number` | `0` | Visual shift (no DOM change) |
| `flex` | `number \| string` | — | CSS flex value |
| `xs/sm/md/lg/xl/xxl` | `number \| ColSize` | — | Responsive config |

`ColSize = { span?, offset?, order?, push?, pull?, flex? }`

### Patterns

```tsx
// Responsive card grid
<Row gutter={[16, 16]}>
  <Col xs={24} sm={12} md={8} lg={6}><Card /></Col>
  <Col xs={24} sm={12} md={8} lg={6}><Card /></Col>
  <Col xs={24} sm={12} md={8} lg={6}><Card /></Col>
  <Col xs={24} sm={12} md={8} lg={6}><Card /></Col>
</Row>

// Flex ratio layout
<Row>
  <Col flex={2}>2/5</Col>
  <Col flex={3}>3/5</Col>
</Row>

// Fixed + auto-fill
<Row>
  <Col flex="100px">Fixed</Col>
  <Col flex="auto">Fills rest</Col>
</Row>

// Responsive hook
const screens = useBreakpoint();
// { xs: true, sm: true, md: false, ... }
const isMobile = !screens.md;
```

### Common Mistakes
- **Spans must sum ≤ 24** or columns wrap (by design)
- **`gutter` adds padding to Col, negative margin to Row** — don't add extra padding to Col children
- **Nested grids**: always `Row > Col > Row > Col` — never Col directly inside Col
- **`offset` vs `push`**: `offset` counts toward total span, `push` is visual-only
- **Breakpoints are mobile-first** — `xs` applies at all sizes unless overridden
- **`useBreakpoint` may return `undefined` on SSR** — use strict `=== true` comparisons

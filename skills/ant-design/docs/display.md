# Ant Design — Display Components (Typography, Card, List, Descriptions, Space, Flex)

## Typography

```typescript
import { Typography } from 'antd';
const { Title, Text, Paragraph, Link } = Typography;
```

### Sub-components

| Component | Element | Use |
|-----------|---------|-----|
| `Typography.Title` | `<h1>`–`<h5>` | Headings |
| `Typography.Text` | `<span>` | Inline text, labels |
| `Typography.Paragraph` | `<div>` | Multi-line blocks |
| `Typography.Link` | `<a>` | Anchor links |

### Shared Props (all sub-components)

| Prop | Type | Description |
|------|------|-------------|
| `type` | `'secondary' \| 'success' \| 'warning' \| 'danger'` | Semantic color |
| `disabled` | `boolean` | Gray disabled state |
| `code` | `boolean` | `<code>` styling |
| `mark` | `boolean` | `<mark>` highlight |
| `underline` | `boolean` | Underline |
| `delete` | `boolean` | Strikethrough |
| `strong` | `boolean` | Bold |
| `italic` | `boolean` | Italic |
| `keyboard` | `boolean` | `<kbd>` styling |
| `copyable` | `boolean \| CopyConfig` | Copy to clipboard button |
| `editable` | `boolean \| EditConfig` | Inline editing |
| `ellipsis` | `boolean \| EllipsisConfig` | Text truncation |

### Title-specific
- `level`: `1 | 2 | 3 | 4 | 5` — heading level (default `1`)

### EllipsisConfig
```typescript
{
  rows?: number;             // max rows before truncation (default 1)
  expandable?: boolean | 'collapsible'; // show expand; 'collapsible' also collapses
  suffix?: string;           // appended after truncation
  symbol?: ReactNode | ((expanded) => ReactNode); // custom expand symbol
  tooltip?: ReactNode | TooltipProps; // tooltip when ellipsed
  expanded?: boolean;        // controlled expand state
  onExpand?: (e, { expanded }) => void;
}
```

### CopyConfig
```typescript
{
  text?: string | (() => string | Promise<string>); // text to copy
  onCopy?: () => void;
  icon?: ReactNode;        // [copyIcon, copiedIcon]
  tooltips?: ReactNode;    // [hover, success] — false hides
  format?: 'text/plain' | 'text/html';
}
```

### EditConfig
```typescript
{
  text?: string;           // controlled edit text
  editing?: boolean;       // controlled editing state
  onChange?: (value) => void;
  onStart?: () => void;
  onCancel?: () => void;
  onEnd?: () => void;
  maxLength?: number;
  autoSize?: boolean | { minRows?, maxRows? };
  triggerType?: ('icon' | 'text')[];  // default ['icon']
  enterIcon?: ReactNode;   // custom save icon; null to hide
}
```

### Patterns

```tsx
// Text decoration
<Text strong>Bold</Text>
<Text type="secondary">Secondary</Text>
<Text type="danger">Error</Text>
<Text code copyable>const x = 1;</Text>
<Text keyboard>Ctrl</Text>
<Text mark>highlighted</Text>
<Text delete>removed</Text>

// Title
<Title level={2}>Section Title</Title>

// Copyable paragraph (async)
<Paragraph copyable={{ text: async () => fetchSecret(), tooltips: ['Copy', 'Copied!'] }}>
  Click to copy secret
</Paragraph>

// Editable — click text to edit
<Paragraph
  editable={{ onChange: setText, triggerType: ['text'], maxLength: 200 }}>
  {text}
</Paragraph>

// Ellipsis with expand/collapse
<Paragraph ellipsis={{ rows: 3, expandable: 'collapsible', expanded, onExpand: (_, { expanded }) => setExpanded(expanded) }}>
  {longText}
</Paragraph>

// Tooltip when truncated
<Text style={{ width: 200 }} ellipsis={{ tooltip: 'Full text here' }}>{longText}</Text>

// Link
<Link href="https://ant.design" target="_blank">Ant Design</Link>
```

### Common Mistakes
- **`copyable` without `text` prop** copies all rendered children including markup — set `text` explicitly
- **`ellipsis` requires fixed-width container** — wrap in `<div style={{ width: 300 }}>`
- **`Text` supports single-line ellipsis only** — `rows` and `expandable` are not available on `Text`

---

## Card

```typescript
import { Card } from 'antd';
```

### CardProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `ReactNode` | — | Card header content |
| `extra` | `ReactNode` | — | Top-right header content |
| `cover` | `ReactNode` | — | Cover image/content above body |
| `actions` | `ReactNode[]` | — | Bottom action icons/links |
| `loading` | `boolean` | `false` | Show skeleton loading |
| `hoverable` | `boolean` | `false` | Hover lift effect |
| `size` | `'medium' \| 'small'` | `'medium'` | Card padding |
| `type` | `'inner'` | — | Nested card style |
| `variant` | `'outlined' \| 'borderless'` | `'outlined'` | Visual variant (replaces `bordered`) |
| `tabList` | `{ key, label }[]` | — | Tabs in card header |
| `activeTabKey` | `string` | — | Controlled active tab |
| `onTabChange` | `(key) => void` | — | Tab change handler |
| `styles` | `{ header?, body?, cover?, actions? }` | — | Semantic inline styles |
| `classNames` | `{ header?, body?, cover?, actions? }` | — | Semantic CSS classes |

### Sub-components

**`Card.Meta`** — avatar + title + description block:
```typescript
<Card.Meta
  avatar={<Avatar src={url} />}
  title="Card Title"
  description="Description text"
/>
```

**`Card.Grid`** — equal-width grid cells inside a card:
```typescript
<Card.Grid style={{ width: '25%' }} hoverable={false}>Cell content</Card.Grid>
```

### Patterns

```tsx
// Basic with extra action
<Card title="Users" extra={<Button type="link">View all</Button>} style={{ width: 300 }}>
  <p>Card content</p>
</Card>

// Cover + Meta + Actions (media card)
<Card
  style={{ width: 300 }}
  cover={<img alt="cover" src={imageUrl} style={{ height: 200, objectFit: 'cover' }} />}
  actions={[<EditOutlined key="edit" />, <EllipsisOutlined key="more" />]}
>
  <Card.Meta
    avatar={<Avatar src={avatarUrl} />}
    title="John Doe"
    description="Software Engineer"
  />
</Card>

// Loading state
<Card loading={isLoading} actions={actions}>
  <Card.Meta title="Title" description="Description" />
</Card>

// Card with tabs
const [tab, setTab] = useState('tab1');
const content = { tab1: <Content1 />, tab2: <Content2 /> };
<Card title="Dashboard"
  tabList={[{ key: 'tab1', label: 'Overview' }, { key: 'tab2', label: 'Details' }]}
  activeTabKey={tab} onTabChange={setTab}>
  {content[tab]}
</Card>

// Grid layout
<Card title="Team">
  {members.map(m => (
    <Card.Grid key={m.id} style={{ width: '25%', textAlign: 'center' }}>
      <Avatar src={m.avatar} /><br />{m.name}
    </Card.Grid>
  ))}
</Card>

// Inner (nested) card
<Card title="Outer Card">
  <Card type="inner" title="Inner Card" extra={<a href="#">More</a>}>
    Nested content
  </Card>
</Card>

// Borderless
<Card variant="borderless">No border</Card>
```

### Common Mistakes
- **`bordered` is deprecated** — use `variant="outlined"` or `variant="borderless"`
- **`headStyle`/`bodyStyle` are deprecated** — use `styles.header` / `styles.body`
- **`size="default"` is deprecated** — use `size="medium"`

---

## List

```typescript
import { List } from 'antd';
```

> **Deprecation notice:** `List` will be removed in antd v6. The replacement will be `Listy` with built-in virtual scrolling.

### ListProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `dataSource` | `T[]` | `[]` | Data array |
| `renderItem` | `(item, index) => ReactNode` | — | Item renderer |
| `itemLayout` | `'horizontal' \| 'vertical'` | `'horizontal'` | Item layout |
| `bordered` | `boolean` | `false` | Show border |
| `split` | `boolean` | `true` | Dividers between items |
| `loading` | `boolean \| SpinProps` | `false` | Loading state |
| `loadMore` | `ReactNode` | — | "Load more" content at bottom |
| `pagination` | `PaginationConfig \| false` | `false` | Pagination |
| `grid` | `ListGridType` | — | Grid layout config |
| `size` | `'small' \| 'default' \| 'large'` | `'default'` | Item size |
| `header` | `ReactNode` | — | List header |
| `footer` | `ReactNode` | — | List footer |
| `rowKey` | `((item) => Key) \| keyof T` | — | Unique key per item |
| `locale` | `{ emptyText: ReactNode }` | — | Empty state text |

### ListGridType
```typescript
{
  gutter?: number;
  column?: number;
  xs?: number; sm?: number; md?: number;
  lg?: number; xl?: number; xxl?: number;
}
```

### List.Item Props
- `actions?: ReactNode[]` — action links/buttons on the right
- `extra?: ReactNode` — extra content (right side in vertical layout)

### List.Item.Meta Props
- `avatar?: ReactNode`, `title?: ReactNode`, `description?: ReactNode`

### Patterns

```tsx
// Basic horizontal list
<List
  dataSource={users}
  rowKey="id"
  renderItem={(user) => (
    <List.Item actions={[<a key="edit">Edit</a>, <a key="del">Delete</a>]}>
      <List.Item.Meta
        avatar={<Avatar src={user.avatar} />}
        title={<a href="#">{user.name}</a>}
        description={user.email}
      />
    </List.Item>
  )}
/>

// Responsive grid list (card grid)
<List
  grid={{ gutter: 16, xs: 1, sm: 2, md: 3, lg: 4, xl: 4 }}
  dataSource={items}
  renderItem={(item) => (
    <List.Item>
      <Card title={item.title}>Content</Card>
    </List.Item>
  )}
/>

// Vertical layout with cover
<List
  itemLayout="vertical"
  dataSource={articles}
  renderItem={(a) => (
    <List.Item extra={<img width={200} src={a.cover} alt="cover" />}>
      <List.Item.Meta title={<a href="#">{a.title}</a>} description={a.author} />
      {a.excerpt}
    </List.Item>
  )}
/>

// Load more pattern
const [data, setData] = useState([]);
const [loading, setLoading] = useState(false);
const loadMore = !loading ? (
  <div style={{ textAlign: 'center', margin: '12px 0' }}>
    <Button onClick={fetchMore}>Load more</Button>
  </div>
) : null;
<List dataSource={data} loadMore={loadMore} renderItem={...} />
```

### Common Mistakes
- **Missing `rowKey`** causes React reconciliation issues with dynamic data
- **Pagination doesn't fetch data** — you must handle page changes in `onChange`

---

## Descriptions

```typescript
import { Descriptions } from 'antd';
import type { DescriptionsProps } from 'antd';
```

### DescriptionsProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `items` | `DescriptionsItemType[]` | — | **Preferred** (v5.8+). Item definitions array |
| `title` | `ReactNode` | — | Header title |
| `extra` | `ReactNode` | — | Top-right corner content |
| `bordered` | `boolean` | `false` | Table-style borders |
| `layout` | `'horizontal' \| 'vertical'` | `'horizontal'` | Orientation |
| `column` | `number \| Partial<Record<Breakpoint, number>>` | `3` | Items per row (responsive object supported) |
| `size` | `'large' \| 'medium' \| 'small'` | `'medium'` | Row padding |
| `colon` | `boolean` | `true` | Show colon after label |
| `styles` | `{ label?, content?, header?, root? }` | — | Semantic inline styles |
| `classNames` | `{ label?, content?, header?, root? }` | — | Semantic CSS classes |

### DescriptionsItemType
```typescript
{
  key?: React.Key;
  label?: ReactNode;
  children?: ReactNode;
  span?: number | 'filled' | Partial<Record<Breakpoint, number>>;
  styles?: { label?, content? };
  classNames?: { label?, content? };
}
```

### Patterns

```tsx
// Basic (modern items API)
const items: DescriptionsProps['items'] = [
  { key: '1', label: 'Name',    children: 'John Doe' },
  { key: '2', label: 'Email',   children: 'john@example.com' },
  { key: '3', label: 'Status',  children: <Badge status="processing" text="Active" /> },
  { key: '4', label: 'Address', children: '123 Main St', span: 2 },
];
<Descriptions title="User Info" bordered items={items} />

// Responsive columns
<Descriptions
  column={{ xs: 1, sm: 2, md: 3, lg: 4 }}
  items={items}
/>

// Vertical layout (label above value)
<Descriptions layout="vertical" bordered items={items} />

// With extra action
<Descriptions title="Details" extra={<Button>Edit</Button>} bordered items={items} />

// Per-item label/content styling
const styledItems: DescriptionsProps['items'] = [
  {
    label: 'Priority',
    children: 'High',
    styles: {
      label: { fontWeight: 'bold', color: '#1677ff' },
      content: { color: 'red' },
    },
  },
];

// Span = 'filled' (takes remaining columns in row)
{ label: 'Notes', children: 'Long text...', span: 'filled' }
```

### Common Mistakes
- **`children` JSX approach is deprecated** (v5.8+) — use `items` prop
- **`labelStyle`/`contentStyle` props deprecated** — use `styles.label` / `styles.content`
- **`column` should use responsive object** for proper mobile behavior
- **`span` must not exceed `column` count** — excess span is ignored

---

## Space

```typescript
import { Space } from 'antd';
// Sub-components:
// Space.Compact — merge borders between inputs/buttons
// Space.Addon (v5.29+) — styled addon cell ($ sign, units, etc.)
```

### SpaceProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `size` | `'small' \| 'medium' \| 'large' \| number \| [h, v]` | `'small'` | Gap size; tuple for [horizontal, vertical] |
| `orientation` | `'horizontal' \| 'vertical'` | `'horizontal'` | Layout direction |
| `vertical` | `boolean` | — | Shorthand for `orientation="vertical"` |
| `align` | `'start' \| 'end' \| 'center' \| 'baseline'` | — | Cross-axis alignment |
| `wrap` | `boolean` | `false` | Wrap items to next line |
| `separator` | `ReactNode` | — | Separator between items |
| `classNames` | `{ root?, item?, separator? }` | — | Semantic class names |
| `styles` | `{ root?, item?, separator? }` | — | Semantic inline styles |

### Space.Compact — for input/button groups

Collapses borders between: Button, Input (all variants), Select, DatePicker, InputNumber, AutoComplete, Cascader, TimePicker, TreeSelect, ColorPicker.

```typescript
interface SpaceCompactProps {
  size?: 'small' | 'medium' | 'large';
  orientation?: 'horizontal' | 'vertical';
  vertical?: boolean;
  block?: boolean;  // full width
}
```

### Patterns

```tsx
// Inline button row
<Space>
  <Button type="primary">Save</Button>
  <Button>Cancel</Button>
  <Button danger>Delete</Button>
</Space>

// Vertical form layout
<Space orientation="vertical" style={{ width: '100%' }}>
  <Input placeholder="Name" />
  <Input placeholder="Email" />
  <Button type="primary" block>Submit</Button>
</Space>

// Custom gap
<Space size={[32, 16]} wrap>
  {tags.map(t => <Tag key={t}>{t}</Tag>)}
</Space>

// With separator
<Space separator={<Divider type="vertical" />}>
  <Link>Home</Link>
  <Link>Products</Link>
  <Link>About</Link>
</Space>

// Space.Compact — URL input + button
<Space.Compact block>
  <Input defaultValue="https://" style={{ width: 'calc(100% - 100px)' }} />
  <Button type="primary">Go</Button>
</Space.Compact>

// Space.Compact — Select + Input
<Space.Compact block>
  <Select defaultValue="CN" options={[{ value: 'CN', label: '+86' }]} style={{ width: 80 }} />
  <Input placeholder="Phone number" />
</Space.Compact>

// Space.Compact — with Addon (currency input)
<Space.Compact>
  <Space.Addon>$</Space.Addon>
  <InputNumber placeholder="Amount" style={{ width: '100%' }} />
  <Space.Addon>USD</Space.Addon>
</Space.Compact>

// Vertical compact (button group)
<Space.Compact orientation="vertical">
  <Button>Top</Button>
  <Button>Middle</Button>
  <Button>Bottom</Button>
</Space.Compact>
```

### Common Mistakes
- **`direction` prop is deprecated** — use `orientation` or `vertical`
- **`split` prop is deprecated** — use `separator`
- **`Space` wraps each child in a `<span>`** — use `Flex` for block-level elements without wrappers

---

## Flex

```typescript
import { Flex } from 'antd';
import type { FlexProps } from 'antd';
// Available from antd v5.10.0
```

**Space vs. Flex:**
- **Space** — wraps children in `<span>`; best for inline button/tag rows
- **Flex** — no wrapper elements; full CSS flexbox control; block-level

### FlexProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `vertical` | `boolean` | `false` | Column direction (`flex-direction: column`) |
| `justify` | CSS `justifyContent` | — | `flex-start`, `center`, `flex-end`, `space-between`, `space-around`, `space-evenly` |
| `align` | CSS `alignItems` | — | `flex-start`, `center`, `flex-end`, `baseline`, `stretch` |
| `gap` | `'small' \| 'medium' \| 'large' \| number \| string` | — | Gap between children |
| `wrap` | `boolean \| CSS flexWrap` | — | Enable wrapping |
| `flex` | CSS `flex` | — | Flex shorthand on the container |
| `component` | `keyof JSX.IntrinsicElements` | `'div'` | Underlying element |

### Patterns

```tsx
// Horizontal row, center-aligned
<Flex justify="space-between" align="center">
  <h2>Title</h2>
  <Button type="primary">Add</Button>
</Flex>

// Vertical stack (form layout)
<Flex vertical gap="middle" style={{ width: '100%' }}>
  <Input placeholder="Name" />
  <Input placeholder="Email" />
  <Button type="primary" block>Submit</Button>
</Flex>

// Responsive card grid
<Flex wrap gap="middle">
  {items.map(i => (
    <div key={i.id} style={{ flex: '0 0 calc(25% - 12px)' }}>
      <Card title={i.title}>Content</Card>
    </div>
  ))}
</Flex>

// Full-width sidebar + main layout
<Flex style={{ height: '100vh' }}>
  <Flex vertical style={{ width: 240, borderRight: '1px solid #f0f0f0' }}>
    <Menu mode="inline" items={menuItems} />
  </Flex>
  <Flex vertical flex="1" style={{ padding: 24 }}>
    {children}
  </Flex>
</Flex>

// Card with image + content side by side
<Card styles={{ body: { padding: 0 } }}>
  <Flex>
    <img src={imageUrl} style={{ width: 200, objectFit: 'cover' }} alt="cover" />
    <Flex vertical justify="space-between" style={{ padding: 24, flex: 1 }}>
      <Typography.Title level={4}>{title}</Typography.Title>
      <Button type="primary">Learn more</Button>
    </Flex>
  </Flex>
</Card>

// Centered loading state
<Flex justify="center" align="center" style={{ height: 200 }}>
  <Spin tip="Loading..." />
</Flex>

// As semantic HTML
<Flex component="section" vertical gap={16}>
  <Flex component="article">Article 1</Flex>
  <Flex component="article">Article 2</Flex>
</Flex>
```

### Common Mistakes
- **Flex items with text can overflow** — add `minWidth: 0` on flex children containing long text
- **Flex doesn't fill height by default** — add `style={{ height: '100%' }}` or `flex="1"` as needed
- **`gap` with number is px** — `gap={16}` = `16px`; preset strings map to theme spacing tokens

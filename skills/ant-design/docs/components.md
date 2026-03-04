# Ant Design — All Components Reference

All components: `import { ComponentName } from 'antd'`
Icons: `import { IconName } from '@ant-design/icons'`

---

## General (3)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **Button** | `type`, `color`, `variant`, `size`, `shape`, `loading`, `danger`, `ghost`, `icon`, `htmlType` | See `key-components.md` for full API |
| **Icon** | `style`, `spin`, `rotate`, `twoToneColor` | From `@ant-design/icons`; `Outlined`/`Filled`/`TwoTone` suffixes |
| **Typography** | — | Sub: `Title` (h1-h5), `Text` (copyable, code, delete, editable), `Link`, `Paragraph` |

---

## Layout (6)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **Divider** | `type` (horizontal/vertical), `orientation`, `dashed`, `plain` | |
| **Flex** | `justify`, `align`, `gap`, `wrap`, `vertical` | CSS Flexbox abstraction; v5.10+ |
| **Grid** (Row/Col) | `Row: gutter, justify, align, wrap` / `Col: span, offset, xs, sm, md, lg, xl` | 24-column grid |
| **Layout** | `hasSider` | Sub: `Header`, `Content`, `Footer`, `Sider` (collapsible, width, breakpoint) |
| **Space** | `size`, `direction`, `wrap`, `align`, `split` | Inline gap management |
| **Splitter** | `layout` (horizontal/vertical), `onResize`, `onResizeEnd` | Resizable panels; v5.21+ |

---

## Navigation (8)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **Affix** | `offsetTop`, `offsetBottom`, `target`, `onChange` | Sticky element |
| **Anchor** | `items`, `affix`, `offsetTop`, `targetOffset`, `onChange` | Jump links |
| **Breadcrumb** | `items[{ title, href, onClick }]`, `separator` | |
| **Dropdown** | `menu`, `open`, `trigger`, `placement`, `arrow` | `menu.items` array |
| **Menu** | `items`, `mode` (horizontal/vertical/inline), `theme`, `selectedKeys`, `openKeys`, `onSelect` | |
| **Pagination** | `total`, `pageSize`, `current`, `showSizeChanger`, `showQuickJumper`, `onChange` | |
| **Steps** | `items[{ title, description, status, icon }]`, `current`, `direction`, `type` | |
| **FloatButton** | `icon`, `tooltip`, `type`, `shape`, `onClick` | Sub: `FloatButton.Group`, `FloatButton.BackTop`; v5.0+ |

---

## Data Entry (19)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **AutoComplete** | `options`, `onSearch`, `onSelect`, `filterOption` | Input with suggestions |
| **Cascader** | `options`, `value`, `onChange`, `multiple`, `showSearch`, `changeOnSelect` | Multi-level selector |
| **Checkbox** | `checked`, `onChange`, `disabled`, `indeterminate` | `Checkbox.Group: options, value` |
| **ColorPicker** | `value`, `onChange`, `format`, `presets`, `showText` | v5.5+ |
| **DatePicker** | `picker`, `value`, `onChange`, `showTime`, `format`, `disabledDate`, `needConfirm` | Uses dayjs; `RangePicker` for ranges |
| **Form** | — | See `key-components.md` |
| **Input** | `value`, `onChange`, `allowClear`, `prefix`, `suffix`, `addonBefore`, `addonAfter`, `showCount`, `maxLength` | Sub: `TextArea`, `Password`, `Search` |
| **InputNumber** | `min`, `max`, `step`, `precision`, `formatter`, `parser`, `addonBefore`, `addonAfter` | |
| **Mentions** | `options`, `prefix`, `onSearch`, `onSelect` | @mention input |
| **Radio** | `value`, `onChange` | `Radio.Group: options, value, buttonStyle` / `Radio.Button` |
| **Rate** | `count`, `value`, `onChange`, `allowHalf`, `character` | Star rating |
| **Select** | `mode` (multiple/tags), `options`, `value`, `onChange`, `showSearch`, `filterOption`, `allowClear`, `loading`, `fieldNames`, `labelInValue` | |
| **Segmented** | `options`, `value`, `onChange`, `block`, `size` | Button-group toggle |
| **Slider** | `min`, `max`, `step`, `value`, `onChange`, `range`, `marks`, `tooltip` | Range or single |
| **Switch** | `checked`, `onChange`, `checkedChildren`, `unCheckedChildren`, `loading` | |
| **TimePicker** | `value`, `onChange`, `format`, `use12Hours`, `showNow`, `disabledTime` | |
| **Transfer** | `dataSource`, `targetKeys`, `onChange`, `titles`, `render`, `listStyle` | Dual-panel list |
| **TreeSelect** | `treeData`, `value`, `onChange`, `multiple`, `showSearch`, `treeCheckable` | |
| **Upload** | `action`, `accept`, `multiple`, `fileList`, `onChange`, `beforeUpload`, `listType`, `maxCount` | `listType: 'text' \| 'picture' \| 'picture-card'` |

---

## Data Display (20)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **Avatar** | `src`, `icon`, `size`, `shape` (circle/square), `alt` | `Avatar.Group: max, size` |
| **Badge** | `count`, `dot`, `status`, `color`, `overflowCount`, `showZero`, `offset` | Wraps child |
| **Calendar** | `value`, `onSelect`, `dateCellRender`, `monthCellRender`, `mode`, `fullscreen` | |
| **Card** | `title`, `extra`, `loading`, `actions`, `hoverable`, `cover`, `tabList` | Sub: `Card.Meta`, `Card.Grid` |
| **Carousel** | `autoplay`, `dots`, `effect`, `arrows`, `afterChange` | |
| **Collapse** | `items[{ key, label, children }]`, `accordion`, `defaultActiveKey` | |
| **Descriptions** | `items[{ key, label, children, span }]`, `column`, `layout`, `bordered`, `title` | Key-value display |
| **Empty** | `image`, `description`, `imageStyle` | No-data placeholder |
| **Image** | `src`, `width`, `height`, `preview`, `fallback` | `Image.PreviewGroup` for gallery |
| **List** | `dataSource`, `renderItem`, `grid`, `pagination`, `loading` | Sub: `List.Item`, `List.Item.Meta` |
| **Popover** | `content`, `title`, `trigger`, `placement`, `open` | Richer than Tooltip |
| **QRCode** | `value`, `size`, `color`, `bgColor`, `icon`, `status` | v5.1+ |
| **Statistic** | `value`, `title`, `prefix`, `suffix`, `formatter`, `precision` | `Statistic.Countdown` |
| **Table** | — | See `key-components.md` |
| **Tabs** | `items[{ key, label, children }]`, `activeKey`, `onChange`, `type`, `tabPosition`, `tabBarExtraContent` | |
| **Tag** | `color`, `closable`, `onClose`, `bordered` | Preset or hex color |
| **Timeline** | `items[{ color, dot, label, children }]`, `mode`, `pending`, `reverse` | |
| **Tooltip** | `title`, `placement`, `trigger`, `open`, `color` | Light hover text |
| **Tree** | `treeData`, `checkable`, `defaultExpandAll`, `onCheck`, `onSelect`, `draggable` | |
| **Watermark** | `content`, `font`, `image`, `rotate`, `gap`, `offset` | v5.1+ |

---

## Feedback (11)

| Component | Key Props | Notes |
|-----------|-----------|-------|
| **Alert** | `type` (success/info/warning/error), `message`, `description`, `closable`, `action`, `showIcon`, `banner` | Inline banner |
| **Drawer** | `open`, `onClose`, `title`, `placement`, `width`, `height`, `mask`, `extra`, `footer` | Slide-in panel |
| **Message** | — | Imperative: `message.success/error/warning/info/loading(content, duration)` |
| **Modal** | — | See `key-components.md` |
| **Notification** | — | `notification.success/error/warning/info({ message, description, placement, duration })` |
| **Popconfirm** | `title`, `onConfirm`, `onCancel`, `okText`, `cancelText`, `okButtonProps`, `placement` | Bubble confirm |
| **Progress** | `percent`, `type` (line/circle/dashboard), `status`, `strokeColor`, `format`, `steps` | |
| **Result** | `status` (success/error/warning/404/403/500), `title`, `subTitle`, `extra` | Full-page outcome |
| **Skeleton** | `active`, `paragraph`, `avatar`, `title`, `loading` | Loading placeholder |
| **Spin** | `spinning`, `tip`, `size`, `delay`, wraps content | Loading overlay |
| **Tour** | `open`, `onClose`, `steps[{ title, description, target, cover }]` | Guided tour; v5.0+ |

---

## Utility Components

| Component | Notes |
|-----------|-------|
| **App** | Wrap root: `<App>`. Use `App.useApp()` for context-aware `message`, `modal`, `notification` |
| **ConfigProvider** | Global theme, locale, direction, componentSize, virtual, getPopupContainer |

---

## Quick Import Reference

```tsx
// Single import covers everything — fully tree-shaken
import {
  // Layout
  Layout, Grid, Row, Col, Space, Flex, Divider,
  // Navigation
  Menu, Breadcrumb, Pagination, Steps, Tabs, Dropdown,
  // Data Entry
  Form, Input, Select, DatePicker, Checkbox, Radio, Switch, Upload, Slider,
  InputNumber, AutoComplete, Cascader, Rate, Transfer, Mentions, TimePicker,
  // Data Display
  Table, Card, List, Avatar, Badge, Tag, Tooltip, Popover, Tree, Image,
  Collapse, Carousel, Timeline, Descriptions, Statistic, QRCode, Calendar,
  // Feedback
  Modal, Drawer, Alert, Spin, Progress, Skeleton, Result, Popconfirm,
  // Utility
  ConfigProvider, App,
  // Imperative APIs
  message, notification,
  // Theme
  theme,
} from 'antd';

// Icons (separate package)
import { SearchOutlined, PlusOutlined, DeleteFilled } from '@ant-design/icons';

// TypeScript types
import type {
  ButtonProps, InputProps, SelectProps, FormInstance, FormProps,
  TableColumnsType, TableProps, TablePaginationConfig,
  ModalProps, DrawerProps, MenuProps, TabsProps, ThemeConfig,
} from 'antd';
```

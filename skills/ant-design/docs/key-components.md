# Ant Design — Form, Table, Modal, Button Deep Reference

---

## FORM

### Form Props

| Prop | Type | Default | Notes |
|------|------|---------|-------|
| `form` | `FormInstance` | — | Created by `Form.useForm()` |
| `layout` | `horizontal \| vertical \| inline` | `horizontal` | |
| `initialValues` | `object` | — | **Not reactive after mount** — use `setFieldsValue()` for async data |
| `onFinish` | `(values) => void` | — | Called after successful validation |
| `onFinishFailed` | `({ values, errorFields }) => void` | — | Called when validation fails |
| `onValuesChange` | `(changed, all) => void` | — | Fires on any change |
| `disabled` | `boolean` | `false` | Disables all antd controls |
| `size` | `small \| middle \| large` | — | |
| `variant` | `outlined \| borderless \| filled \| underlined` | `outlined` | |
| `requiredMark` | `boolean \| 'optional'` | `true` | |
| `labelCol` | `ColProps` | — | Grid layout for labels |
| `wrapperCol` | `ColProps` | — | Grid layout for inputs |
| `scrollToFirstError` | `boolean \| ScrollOptions` | `false` | |
| `validateMessages` | `ValidateMessages` | — | Override validation message templates |
| `preserve` | `boolean` | `true` | Keep unmounted field values |

### Form.Item Props

| Prop | Type | Notes |
|------|------|-------|
| `name` | `string \| number \| (string\|number)[]` | Field path; supports nested `['user', 'address']` |
| `label` | `ReactNode` | |
| `rules` | `Rule[]` | |
| `required` | `boolean` | Shows asterisk only; add rule for actual validation |
| `valuePropName` | `string` | Use `'checked'` for Checkbox/Switch (default: `'value'`) |
| `validateTrigger` | `string \| string[]` | When to validate (default: `'onChange'`) |
| `dependencies` | `NamePath[]` | Re-validates when listed fields change |
| `noStyle` | `boolean` | Removes visual styling; field still registers |
| `hasFeedback` | `boolean` | Shows validation status icon |
| `initialValue` | any | Field-level default; overrides Form `initialValues` for this field |
| `tooltip` | `ReactNode \| TooltipProps` | Tooltip on label |
| `normalize` | `(value, prev, all) => any` | Transform value before storing |
| `getValueFromEvent` | `(event) => any` | Extract value from change event |

### FormInstance Methods

```tsx
const [form] = Form.useForm<MyValues>();

// Reading
form.getFieldValue('email');
form.getFieldsValue(['email', 'name']);
form.getFieldsValue(true);              // all including unstored
form.getFieldError('email');            // string[]
form.isFieldTouched('email');           // boolean

// Writing
form.setFieldValue('email', 'x@x.com');
form.setFieldsValue({ email: 'x', name: 'y' });

// Validation
form.validateFields();                  // Promise<Values>
form.validateFields(['email', 'name']);

// Reset & Scroll
form.resetFields();
form.resetFields(['email']);
form.scrollToField('email');

// Programmatic submit
form.submit();
```

### Hooks

```tsx
// Reactive field watch — preferred over getFieldValue in render
const email = Form.useWatch('email', form);
const address = Form.useWatch(['user', 'address'], form); // nested

// Access form status inside custom component inside Form.Item
const { status, errors } = Form.Item.useStatus();

// Get nearest ancestor form without prop drilling
const form = Form.useFormInstance();
```

### Validation Rules

```tsx
rules={[
  { required: true, message: 'Required' },
  { type: 'email', message: 'Invalid email' },
  { type: 'url' },
  { min: 6, max: 50 },
  { len: 11, message: 'Must be exactly 11 chars' },
  { pattern: /^[a-z]+$/i, message: 'Letters only' },
  { whitespace: true, message: 'Cannot be only whitespace' },
  { warningOnly: true, message: 'This is just a warning' },

  // Async validator
  {
    validator: async (_, value) => {
      if (!value || value.length < 3) throw new Error('Too short');
    },
  },

  // Cross-field (compare with another field)
  ({ getFieldValue }) => ({
    validator(_, value) {
      if (!value || getFieldValue('password') === value) return Promise.resolve();
      return Promise.reject(new Error('Passwords must match'));
    },
  }),
]}
```

### Form.List — Dynamic Fields

```tsx
<Form.List name="users">
  {(fields, { add, remove }) => (
    <>
      {fields.map((field) => (
        <Form.Item key={field.key}>
          <Form.Item {...field} name={[field.name, 'email']} noStyle
            rules={[{ type: 'email', required: true }]}>
            <Input placeholder="Email" />
          </Form.Item>
          <Button onClick={() => remove(field.name)}>Remove</Button>
        </Form.Item>
      ))}
      <Button onClick={() => add()}>Add</Button>
      <Button onClick={() => add({ email: 'default@example.com' })}>Add with Default</Button>
    </>
  )}
</Form.List>
```

### Common Form Mistakes

1. **`valuePropName="checked"` required for Checkbox/Switch** — otherwise stores event object
2. **`initialValues` is not reactive** — use `form.setFieldsValue()` for async data loads
3. **`htmlType="submit"` required on submit Button** — `onClick={() => form.submit()}` bypasses form events
4. **Do NOT call `form.getFieldsValue()` during render** — use `Form.useWatch()` instead
5. **Do NOT wrap multiple controls in one `Form.Item` with `name`** — use `noStyle` on inner items
6. **`Form.useForm()` only works in functional components** — use `ref` for class components

---

## TABLE

### Table Props

| Prop | Type | Default | Notes |
|------|------|---------|-------|
| `dataSource` | `T[]` | — | Array of data |
| `columns` | `ColumnsType<T>` | — | Column config |
| `rowKey` | `string \| (record) => string` | `'key'` | **Always set this** |
| `pagination` | `TablePaginationConfig \| false` | — | `false` disables pagination |
| `loading` | `boolean \| SpinProps` | `false` | Loading overlay |
| `rowSelection` | `TableRowSelection<T>` | — | Checkbox/radio selection |
| `expandable` | `ExpandableConfig<T>` | — | Expandable rows |
| `onChange` | `(pagination, filters, sorter, extra) => void` | — | Server-side handler |
| `scroll` | `{ x?, y? }` | — | Scrollable area |
| `sticky` | `boolean \| { offsetHeader }` | `false` | Sticky header |
| `virtual` | `boolean` | `false` | Virtual scrolling (requires `scroll.y`) |
| `size` | `large \| middle \| small` | `large` | Density |
| `bordered` | `boolean` | `false` | Cell borders |
| `summary` | `(data) => ReactNode` | — | Summary row |
| `onRow` | `(record, index) => HTMLAttributes` | — | Row event handlers |

### Column Props

| Prop | Type | Notes |
|------|------|-------|
| `title` | `ReactNode` | Header content |
| `dataIndex` | `string \| string[]` | Use array for nested: `['user', 'name']` |
| `key` | `string` | Required if no `dataIndex` |
| `render` | `(value, record, index) => ReactNode` | Custom cell renderer |
| `width` | `string \| number` | **Required with `fixed`** |
| `fixed` | `'left' \| 'right'` | Requires `scroll.x` on table |
| `sorter` | `boolean \| CompareFn \| { compare, multiple }` | |
| `filters` | `{ text, value }[]` | Filter dropdown options |
| `onFilter` | `(value, record) => boolean` | Client-side filter |
| `filterSearch` | `boolean` | Search in filter dropdown |
| `filteredValue` | `any[]` | Controlled filter |
| `sortOrder` | `'ascend' \| 'descend' \| null` | Controlled sort |
| `ellipsis` | `boolean` | Truncate with tooltip |
| `align` | `left \| right \| center` | |
| `responsive` | `Breakpoint[]` | Hide at certain breakpoints |
| `hidden` | `boolean` | v5.13+ — hide column |
| `children` | `ColumnsType<T>` | Grouped header columns |
| `onCell` | `(record, index) => HTMLAttributes` | Cell events/props |
| `shouldCellUpdate` | `(record, prev) => boolean` | Optimize re-renders |

### TypeScript Column Pattern

```tsx
import type { TableColumnsType, TableProps } from 'antd';

const columns: TableColumnsType<User> = [
  {
    title: 'Name', dataIndex: 'name', key: 'name', fixed: 'left', width: 150,
    sorter: (a, b) => a.name.localeCompare(b.name),
  },
  {
    title: 'Status', dataIndex: 'status',
    filters: [{ text: 'Active', value: 'active' }, { text: 'Inactive', value: 'inactive' }],
    onFilter: (value, record) => record.status === value,
    render: (status) => <Tag color={status === 'active' ? 'green' : 'red'}>{status}</Tag>,
  },
  {
    title: 'Actions', key: 'actions', fixed: 'right', width: 120,
    render: (_, record) => <Button onClick={() => edit(record)}>Edit</Button>,
  },
];
```

### Row Selection

```tsx
const [selectedKeys, setSelectedKeys] = useState<React.Key[]>([]);

const rowSelection: TableProps<User>['rowSelection'] = {
  type: 'checkbox',
  selectedRowKeys: selectedKeys,
  onChange: (keys) => setSelectedKeys(keys),
  getCheckboxProps: (record) => ({ disabled: record.status === 'inactive' }),
  selections: [Table.SELECTION_ALL, Table.SELECTION_INVERT, Table.SELECTION_NONE],
  preserveSelectedRowKeys: true,   // keep selection across pages
};
```

### Server-Side onChange

```tsx
const handleChange: TableProps<User>['onChange'] = (pagination, filters, sorter, extra) => {
  // extra.action: 'paginate' | 'sort' | 'filter'
  fetchData({
    page: pagination.current,
    pageSize: pagination.pageSize,
    sortField: Array.isArray(sorter) ? undefined : sorter.field,
    sortOrder: Array.isArray(sorter) ? undefined : sorter.order,
    filters,
  });
};
```

### Common Table Mistakes

1. **Always set `rowKey`** — never use array index; breaks selection/expansion when filtered
2. **Fixed columns require explicit `width` + `scroll.x`** on the table
3. **Nested `dataIndex` needs array** — `['user', 'name']` not `'user.name'`
4. **Memoize `columns`** — `useMemo` prevents table re-renders on every parent render
5. **`virtual` requires `scroll.y`** — needs fixed container height
6. **`sorter` must return `0` for equal items** — not a non-zero value

---

## MODAL

### Modal Props

| Prop | Type | Default | Notes |
|------|------|---------|-------|
| `open` | `boolean` | `false` | Visibility |
| `title` | `ReactNode` | — | Header |
| `footer` | `ReactNode \| null \| function` | OK + Cancel | `null` removes footer |
| `width` | `string \| number \| BreakpointMap` | `520` | Responsive: `{ xs: '95%', md: 600 }` |
| `centered` | `boolean` | `false` | Vertically center |
| `onOk` | `(e) => void` | — | OK button handler |
| `onCancel` | `(e) => void` | — | Cancel/close handler |
| `confirmLoading` | `boolean` | `false` | Loading on OK button |
| `okText` | `ReactNode` | `'OK'` | |
| `cancelText` | `ReactNode` | `'Cancel'` | |
| `okButtonProps` | `ButtonProps` | — | |
| `destroyOnHidden` | `boolean` | `false` | Unmount children when closed (v5.25+) |
| `forceRender` | `boolean` | `false` | Pre-render hidden content |
| `keyboard` | `boolean` | `true` | ESC closes modal |
| `mask` | `boolean` | `true` | Show backdrop |
| `afterClose` | `() => void` | — | After close animation |
| `zIndex` | `number` | `1000` | |
| `classNames` | `{ header, body, footer, mask }` | — | Semantic class overrides |
| `styles` | `{ header, body, footer, mask }` | — | Semantic style overrides |

### Static Methods

```tsx
Modal.confirm({
  title: 'Delete?',
  content: 'This cannot be undone.',
  okText: 'Yes, delete',
  okType: 'danger',
  onOk: async () => { await deleteItem(); }, // Promise keeps OK loading until resolved
});
Modal.info({ ... });
Modal.success({ ... });
Modal.warning({ ... });
Modal.error({ ... });
Modal.destroyAll();

// Update / close returned instance
const instance = Modal.confirm({ ... });
instance.update({ title: 'New title' });
instance.destroy();
```

### useModal — Preferred for Context (theme/locale)

```tsx
const App = () => {
  const [modal, contextHolder] = Modal.useModal();

  return (
    <>
      {contextHolder}   {/* Must be inside context providers */}
      <Button onClick={() => modal.confirm({ title: 'Sure?', onOk: del })}>Delete</Button>
    </>
  );
};
```

### Modal + Form Pattern

```tsx
const EditModal = ({ record, onClose, onSave }) => {
  const [form] = Form.useForm();
  const [loading, setLoading] = useState(false);

  const handleOk = async () => {
    try {
      const values = await form.validateFields();
      setLoading(true);
      await onSave(values);
      onClose();
    } finally {
      setLoading(false);
    }
  };

  return (
    <Modal
      open={!!record}
      title="Edit"
      onOk={handleOk}
      onCancel={onClose}
      confirmLoading={loading}
      destroyOnHidden     // resets form state when closed
      width={600}
    >
      <Form form={form} layout="vertical" initialValues={record}>
        <Form.Item name="name" label="Name" rules={[{ required: true }]}>
          <Input />
        </Form.Item>
      </Form>
    </Modal>
  );
};
```

### Common Modal Mistakes

1. **Use `Modal.useModal()` not `Modal.confirm()`** in app code — static methods lose context
2. **Use `destroyOnHidden`** (v5.25+) not deprecated `destroyOnClose` — ensures form resets
3. **`footer={null}`** removes footer entirely — empty array `[]` shows footer with no buttons
4. **`contextHolder` must be inside relevant providers** to inherit theme/locale context
5. **`onOk` Promise enables auto confirmLoading** in static methods — manual management needed in component form

---

## BUTTON

### Button Props

| Prop | Type | Default | Notes |
|------|------|---------|-------|
| `type` | `primary \| default \| dashed \| text \| link` | `default` | Legacy shorthand |
| `color` | `default \| primary \| danger \| blue \| green \| ...13 presets` | — | v5.21+ |
| `variant` | `outlined \| dashed \| solid \| filled \| text \| link` | — | v5.21+ |
| `size` | `large \| middle \| small` | `middle` | |
| `shape` | `default \| circle \| round` | `default` | |
| `block` | `boolean` | `false` | Full width |
| `loading` | `boolean \| { delay?, icon? }` | `false` | `delay` prevents spinner flash |
| `disabled` | `boolean` | `false` | |
| `danger` | `boolean` | `false` | Red color intent |
| `ghost` | `boolean` | `false` | Transparent bg — for colored backgrounds |
| `icon` | `ReactNode` | — | |
| `iconPosition` | `start \| end` | `start` | |
| `href` | `string` | — | Renders as `<a>` |
| `target` | `string` | — | Used with `href` |
| `htmlType` | `submit \| reset \| button` | `button` | **Must be `submit` in forms** |
| `onClick` | `(event) => void` | — | |

### type → color + variant mapping (v5.21+)

| `type` | Equivalent |
|--------|-----------|
| `primary` | `color="primary" variant="solid"` |
| `default` | `color="default" variant="outlined"` |
| `dashed` | `color="default" variant="dashed"` |
| `text` | `color="default" variant="text"` |
| `link` | `color="default" variant="link"` |
| `primary` + `danger` | `color="danger" variant="solid"` |
| `primary` + `ghost` | `color="primary" variant="outlined"` |

### Common Button Mistakes

1. **`htmlType="submit"` is required** inside `<Form>` — default `"button"` won't trigger `onFinish`
2. **`danger` is a modifier, not a `type`** — there is no `type="danger"`
3. **`ghost` only works on colored backgrounds** — invisible on white
4. **`loading={{ delay: 300 }}`** prevents spinner flash for fast operations
5. **Icon-only buttons need `aria-label`** — `<Button shape="circle" icon={<X />} aria-label="Close" />`
6. **Don't mix `type` and `color+variant` simultaneously** — `color`+`variant` wins

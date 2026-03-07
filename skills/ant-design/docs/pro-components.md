# Ant Design Pro Components (ProTable, ProForm, ProLayout)

```bash
npm install @ant-design/pro-components
```

> Pro Components build on top of antd for enterprise admin UIs. All three share the same package.

---

## ProTable

```typescript
import { ProTable } from '@ant-design/pro-components';
import type { ProColumns, ActionType } from '@ant-design/pro-components';
```

### Core Concept

Every column in `columns` automatically generates a filter form field. The `request` prop handles data fetching with pagination, sorting, and filtering — no manual state management needed.

### ProTableProps (key props)

| Prop | Type | Description |
|------|------|-------------|
| `columns` | `ProColumns<T>[]` | Column + filter form definitions |
| `request` | `(params, sort, filter) => Promise<RequestData<T>>` | Data fetcher — the primary API |
| `actionRef` | `Ref<ActionType>` | Imperative table control (reload, reset, etc.) |
| `dataSource` | `T[]` | Static data (alternative to `request`) |
| `rowKey` | `string \| (r) => string` | Unique row key (default `'id'`) |
| `headerTitle` | `ReactNode` | Title above table |
| `toolBarRender` | `(action, { selectedRows }) => ReactNode[]` | Toolbar elements |
| `search` | `SearchConfig \| false` | Filter form config; `false` = hide |
| `pagination` | `PaginationConfig` | Pagination; default `{ pageSize: 20 }` |
| `rowSelection` | `TableRowSelection<T>` | Row selection config |
| `params` | `Record<string, any>` | Extra params always sent to `request` |
| `options` | `OptionsConfig \| false` | Toolbar icons (reload, density, settings) |
| `dateFormatter` | `'string' \| 'number' \| false` | Auto-format date params in request |

### request function signature

```typescript
type RequestFn<T> = (
  params: {
    pageSize?: number;   // current page size
    current?: number;    // 1-indexed page number
    [filterKey: string]: any;  // filter form values
  },
  sort: Record<string, 'ascend' | 'descend'>,  // column sort state
  filter: Record<string, (string | number)[]>,  // column filter state
) => Promise<{
  data: T[];
  success: boolean;  // REQUIRED — table checks this
  total?: number;    // REQUIRED for pagination
}>
```

### ProColumns

```typescript
type ProColumns<T> = {
  // Standard antd column props
  dataIndex?: string | string[];
  title?: string | ReactNode;
  key?: string;
  width?: number | string;
  fixed?: 'left' | 'right';
  align?: 'left' | 'center' | 'right';
  sorter?: boolean | ((a: T, b: T) => number);
  render?: (text, record: T, index, action: ActionType) => ReactNode;

  // Pro-specific
  valueType?: ProColumnValueType;   // determines filter field and display
  valueEnum?: ValueEnumMap;         // for select/status display
  hideInSearch?: boolean;           // hide from filter form
  hideInTable?: boolean;            // hide from table columns
  copyable?: boolean;               // show copy icon
  ellipsis?: boolean;               // truncate text
  tooltip?: string;                 // column header tooltip
  fieldProps?: Record<string, any>; // props for the filter field component
  formItemProps?: Record<string, any>; // props for Form.Item in filter
  initialValue?: any;               // initial filter value
  request?: () => Promise<{ label, value }[]>; // async options
};
```

### valueType options

| valueType | Table display | Filter field |
|-----------|--------------|--------------|
| `'text'` | plain text | Input |
| `'select'` | badge/label | Select |
| `'date'` | formatted date | DatePicker |
| `'dateTime'` | date + time | DatePicker (time) |
| `'dateRange'` | — | RangePicker |
| `'money'` | `¥1,234.00` | InputNumber |
| `'percent'` | `12%` | InputNumber |
| `'progress'` | ProgressBar | Slider |
| `'status'` | colored badge | Select |
| `'avatar'` | Avatar | — |
| `'image'` | image | — |
| `'switch'` | — | Switch |
| `'option'` | action links | hidden |

### valueEnum format

```typescript
// Object form (key = value, status for badge color)
valueEnum: {
  active:   { text: 'Active',   status: 'success' },
  inactive: { text: 'Inactive', status: 'error' },
  pending:  { text: 'Pending',  status: 'processing' },
}
// status: 'success' | 'error' | 'processing' | 'warning' | 'default'

// Array form
valueEnum: [
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
]
```

### ActionType methods

```typescript
const actionRef = useRef<ActionType>(null);

actionRef.current?.reload();         // reload current page
actionRef.current?.reloadAndRest();  // reload + reset to page 1
actionRef.current?.reset();          // reset filter form only
actionRef.current?.clearSelected();  // clear row selection
```

### Complete example

```tsx
import { ProTable, ActionType } from '@ant-design/pro-components';
import type { ProColumns } from '@ant-design/pro-components';
import { useRef } from 'react';

interface User { id: string; name: string; status: string; createdAt: string; }

const UserTable = () => {
  const actionRef = useRef<ActionType>(null);

  const columns: ProColumns<User>[] = [
    { dataIndex: 'name', title: 'Name' },
    {
      dataIndex: 'status', title: 'Status', valueType: 'select',
      valueEnum: {
        active:   { text: 'Active',   status: 'success' },
        inactive: { text: 'Inactive', status: 'error' },
      },
    },
    { dataIndex: 'createdAt', title: 'Created', valueType: 'dateTime', hideInSearch: true },
    {
      title: 'Actions', valueType: 'option', fixed: 'right', width: 120,
      render: (_, record) => [
        <a key="edit" onClick={() => openEditModal(record)}>Edit</a>,
        <a key="delete" onClick={() => confirmDelete(record.id)}>Delete</a>,
      ],
    },
  ];

  return (
    <ProTable<User>
      actionRef={actionRef}
      columns={columns}
      rowKey="id"
      headerTitle="Users"
      request={async ({ current, pageSize, name, status }) => {
        const res = await api.getUsers({ page: current, size: pageSize, name, status });
        return { data: res.items, success: true, total: res.total };
      }}
      toolBarRender={() => [
        <Button key="add" type="primary" onClick={openCreateModal}>+ Add</Button>,
        <Button key="reload" onClick={() => actionRef.current?.reload()}>Reload</Button>,
      ]}
      search={{ labelWidth: 'auto' }}
      pagination={{ pageSize: 20, showSizeChanger: true }}
    />
  );
};
```

### Common Mistakes
- **Missing `success: true`** in request response — table stays loading forever
- **Missing `total`** — pagination breaks without it
- **`dataIndex` mismatch** — must match your API response field names exactly
- **Filter params are primitives** — complex objects may not serialize correctly in requests

---

## ProForm

```typescript
import {
  ProForm, ProFormText, ProFormSelect, ProFormTextArea,
  ProFormDatePicker, ProFormDateRangePicker, ProFormSwitch,
  ProFormCheckbox, ProFormRadio, ProFormMoney, ProFormUploadButton,
  ProFormDependencies, ModalForm, DrawerForm, QueryFilter, StepsForm,
} from '@ant-design/pro-components';
```

### Core Concept

`onFinish` returns a `Promise` — ProForm automatically manages button loading state. Fields use `name` to bind to form state; `fieldProps` passes props to the underlying component.

### ProFormProps (key props)

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onFinish` | `(values) => Promise<boolean \| void>` | — | Submit handler — **must return a Promise** |
| `initialValues` | `Record<string, any>` | — | Initial form values |
| `layout` | `'horizontal' \| 'vertical' \| 'inline'` | `'vertical'` | Form layout |
| `grid` | `boolean` | `false` | Enable grid layout for fields |
| `colProps` | `ColProps` | — | Default column props for all fields |
| `submitter` | `SubmitterProps \| false` | — | Submit/reset button config; `false` = hide |
| `readonly` | `boolean` | `false` | Read-only display mode |
| `disabled` | `boolean` | `false` | Disable all fields |
| `scrollToFirstError` | `boolean` | — | Scroll to first error on submit |

### Field Width Presets

```typescript
// width prop on any ProFormXxx field
'xs'  // 104px  — short (ID, code)
's'   // 216px  — shorter (name, phone)
'm'   // 328px  — standard (default)
'lg'  // 440px  — long (URL, tag list)
'xl'  // 552px  — very long (description)
```

### ProForm Field Components

All fields share common props:
```typescript
{
  name: string | string[];     // field name (required)
  label?: ReactNode;            // field label
  rules?: Rule[];               // validation rules
  required?: boolean;           // mark as required
  tooltip?: string | ReactNode; // help tooltip
  placeholder?: string;
  width?: 'xs' | 's' | 'm' | 'lg' | 'xl' | number;
  initialValue?: any;
  disabled?: boolean;
  readonly?: boolean;
  fieldProps?: Record<string, any>;      // props for underlying component
  formItemProps?: Record<string, any>;   // props for Form.Item
  colProps?: ColProps;          // column props for grid layout
}
```

### Key Fields

```tsx
// Text input
<ProFormText name="name" label="Name" placeholder="Enter name"
  rules={[{ required: true }, { min: 2 }]} width="m" />

// Password
<ProFormText name="pwd" label="Password" fieldProps={{ type: 'password' }} />

// Textarea
<ProFormTextArea name="bio" label="Bio" fieldProps={{ rows: 4, showCount: true, maxLength: 500 }} />

// Select from options
<ProFormSelect name="role" label="Role"
  options={[{ label: 'Admin', value: 'admin' }, { label: 'User', value: 'user' }]} />

// Select from valueEnum
<ProFormSelect name="status" label="Status"
  valueEnum={{ active: { text: 'Active' }, inactive: { text: 'Inactive' } }} />

// Async select options
<ProFormSelect name="category" label="Category"
  request={async () => {
    const res = await api.getCategories();
    return res.map(c => ({ label: c.name, value: c.id }));
  }} />

// Date picker
<ProFormDatePicker name="date" label="Date" fieldProps={{ format: 'YYYY-MM-DD' }} />

// Date range
<ProFormDateRangePicker name="dateRange" label="Date Range" />

// Switch (boolean)
<ProFormSwitch name="active" label="Active"
  fieldProps={{ checkedChildren: 'On', unCheckedChildren: 'Off' }} />

// Checkbox group
<ProFormCheckbox.Group name="perms" label="Permissions"
  options={[{ label: 'Read', value: 'r' }, { label: 'Write', value: 'w' }]} />

// Radio group
<ProFormRadio.Group name="size" label="Size"
  options={[{ label: 'S', value: 's' }, { label: 'M', value: 'm' }]} />

// Money
<ProFormMoney name="price" label="Price" fieldProps={{ locale: 'en-US' }} />

// Upload
<ProFormUploadButton name="avatar" label="Avatar"
  fieldProps={{ action: '/api/upload', accept: 'image/*', maxCount: 1, listType: 'picture-card' }} />

// Conditional fields (dependencies)
<ProFormDependencies name={['accountType']}>
  {({ accountType }) =>
    accountType === 'business' ? (
      <ProFormText name="companyName" label="Company Name" rules={[{ required: true }]} />
    ) : null
  }
</ProFormDependencies>
```

### ProForm Variants

```tsx
// Modal form (trigger opens a modal with the form)
<ModalForm title="Create User" trigger={<Button type="primary">Add User</Button>}
  onFinish={async (values) => {
    await createUser(values);
    return true; // true closes the modal
  }}>
  <ProFormText name="name" label="Name" rules={[{ required: true }]} />
  <ProFormText name="email" label="Email" rules={[{ type: 'email' }]} />
</ModalForm>

// Drawer form
<DrawerForm title="Edit Record" trigger={<a>Edit</a>}
  drawerProps={{ destroyOnClose: true }}
  onFinish={async (values) => {
    await updateRecord(values);
    return true;
  }}>
  <ProFormText name="title" label="Title" />
</DrawerForm>

// Query filter (horizontal filter bar)
<QueryFilter onFinish={async (filters) => setFilters(filters)} span={8} labelWidth="auto">
  <ProFormText name="keyword" label="Keyword" />
  <ProFormSelect name="status" label="Status" options={statusOptions} />
</QueryFilter>

// Step form
<StepsForm onFinish={async (allValues) => { await submit(allValues); }}>
  <StepsForm.StepForm title="Basic Info">
    <ProFormText name="name" label="Name" rules={[{ required: true }]} />
  </StepsForm.StepForm>
  <StepsForm.StepForm title="Contact">
    <ProFormText name="email" label="Email" rules={[{ required: true, type: 'email' }]} />
  </StepsForm.StepForm>
</StepsForm>
```

### Complete ProForm example

```tsx
const CreateUserForm = () => (
  <ProForm
    layout="vertical"
    grid
    colProps={{ span: 12 }}
    onFinish={async (values) => {
      await api.createUser(values);
      message.success('Created!');
      return true;
    }}
    submitter={{ submitButtonProps: { block: true } }}
  >
    <ProFormText name="firstName" label="First Name" rules={[{ required: true }]} />
    <ProFormText name="lastName" label="Last Name" rules={[{ required: true }]} />
    <ProFormText name="email" label="Email" colProps={{ span: 24 }}
      rules={[{ required: true }, { type: 'email' }]} />
    <ProFormSelect name="role" label="Role" colProps={{ span: 24 }}
      options={[{ label: 'Admin', value: 'admin' }, { label: 'User', value: 'user' }]} />
    <ProFormSwitch name="active" label="Active" initialValue={true} />
  </ProForm>
);
```

### Common Mistakes
- **`onFinish` must return a Promise** — without it, the button loading state doesn't work
- **Return `true` from `onFinish`** in ModalForm/DrawerForm to close the overlay; `false` or throwing keeps it open
- **Component props go in `fieldProps`** — `<ProFormText fieldProps={{ maxLength: 20 }}>`, not as root props
- **Password field**: use `fieldProps={{ type: 'password' }}` on `ProFormText`

---

## ProLayout

```typescript
import { ProLayout, PageContainer } from '@ant-design/pro-components';
```

### Core Concept

ProLayout generates a sidebar menu from a `route` config object. Use `PageContainer` inside to get automatic breadcrumbs, page title, and footer toolbar.

### ProLayoutProps (key props)

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `string \| ReactNode` | `'Ant Design Pro'` | Brand name |
| `logo` | `string \| ReactNode` | — | Logo in sidebar header |
| `layout` | `'side' \| 'top' \| 'mix'` | `'side'` | Menu placement |
| `navTheme` | `'light' \| 'dark' \| 'realDark'` | `'light'` | Sidebar theme |
| `collapsed` | `boolean` | — | Controlled sidebar collapse |
| `onCollapse` | `(collapsed) => void` | — | Collapse state change |
| `siderWidth` | `number` | `256` | Sidebar width (px) |
| `route` | `{ routes: MenuDataItem[] }` | — | Menu tree definition |
| `menuProps` | `MenuProps` | — | Passed to the Menu component |
| `menuDataRender` | `(menuData) => MenuDataItem[]` | — | Transform menu items (e.g., filter by permissions) |
| `rightContentRender` | `(props) => ReactNode` | — | Right side of header (user dropdown, etc.) |
| `headerRender` | `(props) => ReactNode` | — | Completely custom header |
| `footerRender` | `(props) => ReactNode` | — | Footer below content |
| `fixedHeader` | `boolean` | `false` | Sticky header |
| `fixSiderbar` | `boolean` | `false` | Sticky sidebar |
| `token` | `object` | — | Design token overrides |
| `onPageChange` | `(pathname) => void` | — | Navigation change callback |

### MenuDataItem

```typescript
type MenuDataItem = {
  name: string;            // REQUIRED — label text (without this, item is hidden!)
  path?: string;           // URL path
  icon?: ReactNode | string; // icon (string = antd icon name)
  children?: MenuDataItem[];
  hideInMenu?: boolean;    // hide from menu but keep route
  hideChildrenInMenu?: boolean;  // show parent, hide children
  hideInBreadcrumb?: boolean;
  disabled?: boolean;
  access?: string;         // permission key
};
```

### PageContainer Props

| Prop | Type | Description |
|------|------|-------------|
| `header.title` | `ReactNode` | Page title (also shown in browser tab) |
| `header.subTitle` | `ReactNode` | Subtitle |
| `header.extra` | `ReactNode` | Right side of header (action buttons) |
| `header.breadcrumb` | `BreadcrumbProps` | Custom breadcrumb config |
| `footer` | `ReactNode[]` | Footer toolbar (array of buttons) |
| `loading` | `boolean` | Loading state for content |
| `ghost` | `boolean` | Transparent background |
| `fixedHeader` | `boolean` | Sticky page header |

### Patterns

```tsx
// Basic layout with router
const App = () => {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <ProLayout
      title="My App"
      collapsed={collapsed}
      onCollapse={setCollapsed}
      layout="side"
      navTheme="dark"
      route={{
        routes: [
          { path: '/dashboard', name: 'Dashboard', icon: 'dashboard' },
          {
            path: '/users', name: 'Users', icon: 'team',
            children: [
              { path: '/users/list', name: 'All Users' },
              { path: '/users/roles', name: 'Roles' },
            ],
          },
          { path: '/settings', name: 'Settings', icon: 'setting' },
        ],
      }}
      rightContentRender={() => (
        <Space>
          <Avatar src={user.avatar} />
          <Dropdown menu={{ items: userMenuItems }}>
            <span>{user.name}</span>
          </Dropdown>
        </Space>
      )}
      footerRender={() => <Footer style={{ textAlign: 'center' }}>My App © 2024</Footer>}
    >
      <PageContainer header={{ title: 'Dashboard' }}>
        <Content />
      </PageContainer>
    </ProLayout>
  );
};

// Page with action buttons and footer toolbar
<PageContainer
  header={{
    title: 'User Details',
    subTitle: 'View and edit user info',
    extra: [
      <Button key="edit" type="primary">Edit</Button>,
      <Button key="delete" danger>Delete</Button>,
    ],
  }}
  footer={[
    <Button key="cancel">Cancel</Button>,
    <Button key="save" type="primary">Save</Button>,
  ]}
>
  <Descriptions bordered items={userFields} />
</PageContainer>

// Permission-based menu filtering
<ProLayout
  menuDataRender={(menuData) =>
    menuData.filter(item => hasPermission(item.access))
  }
  route={{ routes: allRoutes }}
>
  ...
</ProLayout>
```

### Common Mistakes
- **Menu item without `name` is invisible** — always set `name` on every route
- **Icons as strings**: `icon: 'dashboard'` not `icon: <DashboardOutlined />` (for route configs)
- **`hideInMenu` vs `hideChildrenInMenu`**: former hides the item completely; latter shows parent but hides its sub-items
- **Breadcrumbs come from route `path` hierarchy** — missing intermediate routes creates breadcrumb gaps

---

## When to Use Pro Components

| Use Case | Component |
|----------|-----------|
| Admin table with server-side filter/sort/pagination | `ProTable` |
| Create/edit form in modal or drawer | `ModalForm` / `DrawerForm` |
| Multi-step wizard form | `StepsForm` |
| Horizontal search/filter bar | `QueryFilter` |
| Admin dashboard shell (sidebar + header) | `ProLayout` |
| Page content with breadcrumbs + action buttons | `PageContainer` |

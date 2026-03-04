# Ant Design — Data Entry Components (Select, Upload, DatePicker, Input)

## Select

```typescript
import { Select } from 'antd';
import type { SelectProps, LabeledValue, DefaultOptionType } from 'antd';
```

### SelectProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `options` | `{ label, value, disabled?, title? }[]` | — | Preferred way to define options |
| `mode` | `'multiple' \| 'tags'` | — | Multi-select (`tags` allows new entries) |
| `value` | `string \| number \| string[] \| LabeledValue` | — | Controlled value |
| `defaultValue` | same | — | Initial value (uncontrolled) |
| `placeholder` | `ReactNode` | — | Placeholder when nothing selected |
| `allowClear` | `boolean \| { clearIcon? }` | `false` | Show clear button |
| `showSearch` | `boolean \| SearchConfig` | `false` (single), `true` (multiple) | Enable search |
| `filterOption` | `boolean \| (input, option) => boolean` | `true` | Client-side filter; set `false` for server-side |
| `optionFilterProp` | `string` | `'value'` | Property used for filtering — usually set to `'label'` |
| `loading` | `boolean` | `false` | Show loading spinner |
| `disabled` | `boolean` | `false` | Disable select |
| `labelInValue` | `boolean` | `false` | onChange receives `{ value, label }` instead of raw value |
| `fieldNames` | `{ label?, value?, options? }` | — | Override field names for custom option schemas |
| `maxCount` | `number` | — | Max selectable items (multiple/tags mode) |
| `maxTagCount` | `number \| 'responsive'` | — | Max visible tags |
| `tokenSeparators` | `string[]` | — | Characters that trigger tag creation (tags mode) |
| `virtual` | `boolean` | `true` | Virtual scroll for large option lists |
| `popupRender` | `(menu) => ReactNode` | — | Customize dropdown (add footer/button) |
| `optionRender` | `(option, { index }) => ReactNode` | — | Custom option row renderer |
| `tagRender` | `(props) => ReactNode` | — | Custom tag renderer |
| `getPopupContainer` | `(trigger) => HTMLElement` | `document.body` | Popup container node |
| `status` | `'error' \| 'warning'` | — | Validation status |
| `variant` | `'outlined' \| 'borderless' \| 'filled'` | `'outlined'` | Visual style |
| `size` | `'large' \| 'middle' \| 'small'` | `'middle'` | Input size |
| `onChange` | `(value, option) => void` | — | Value change |
| `onSearch` | `(value: string) => void` | — | Search input change |
| `onSelect` / `onDeselect` | `(value, option) => void` | — | Item selected/removed |
| `onClear` | `() => void` | — | Clear button clicked |

### Patterns

```tsx
// Basic
<Select style={{ width: 200 }} onChange={handleChange}
  options={[{ value: 'a', label: 'Option A' }, { value: 'b', label: 'Option B' }]} />

// Search by label (most common)
<Select showSearch optionFilterProp="label" placeholder="Search..."
  options={options} onChange={setValue} />

// Server-side async search
<Select showSearch filterOption={false} onSearch={debounce(fetchOptions, 300)}
  loading={loading} options={options} placeholder="Type to search..." />

// Multiple with max count
<Select mode="multiple" allowClear maxCount={3}
  placeholder="Select up to 3" options={options} onChange={setValues} />

// labelInValue — get both value and label
<Select labelInValue defaultValue={{ value: 'lucy', label: 'Lucy' }}
  onChange={(v: LabeledValue) => console.log(v.value, v.label)} options={options} />

// Custom option schema (fieldNames)
<Select fieldNames={{ label: 'name', value: 'id' }}
  options={[{ id: 1, name: 'Alice' }, { id: 2, name: 'Bob' }]} />

// Add footer button to dropdown
<Select popupRender={(menu) => (
  <>
    {menu}
    <Divider style={{ margin: '8px 0' }} />
    <Button type="link" onClick={addItem}>+ Add item</Button>
  </>
)} options={options} />
```

### Common Mistakes
- **Default `optionFilterProp` is `'value'`**, not `'label'` — users searching by text see no results unless you set `optionFilterProp="label"`
- **For server-side search, always set `filterOption={false}`** — otherwise antd applies its own client-side filter on top
- **`labelInValue` changes `onChange` signature** to `{ value, label }` — causes TypeScript errors if you mix them
- **`mode="tags"` auto-creates options from typed text** — use `mode="multiple"` to restrict to predefined options
- **`value={undefined}` is not the same as omitting `value`** — don't switch between controlled/uncontrolled

---

## Upload

```typescript
import { Upload } from 'antd';
import type { UploadProps, UploadFile, UploadChangeParam, GetProp } from 'antd';
// Derive FileType from beforeUpload
type FileType = Parameters<GetProp<UploadProps, 'beforeUpload'>>[0];
const { Dragger } = Upload;
```

### UploadProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `action` | `string \| ((file: RcFile) => Promise<string>)` | — | Upload URL |
| `fileList` | `UploadFile[]` | — | Controlled file list — must update in `onChange` |
| `defaultFileList` | `UploadFile[]` | — | Initial files (uncontrolled) |
| `accept` | `string` | — | Accepted MIME types / extensions |
| `multiple` | `boolean` | `false` | Allow multi-file select |
| `maxCount` | `number` | — | Cap number of files |
| `listType` | `'text' \| 'picture' \| 'picture-card' \| 'picture-circle'` | `'text'` | UI style |
| `beforeUpload` | `(file, fileList) => boolean \| Promise \| Upload.LIST_IGNORE` | — | Pre-upload validation |
| `customRequest` | `(options) => void` | — | Replace XHR upload entirely |
| `showUploadList` | `boolean \| { showRemoveIcon?, showPreviewIcon?, ... }` | `true` | List icons config |
| `data` | `object \| ((file) => object \| Promise<object>)` | — | Extra form fields with upload |
| `headers` | `object` | — | Extra HTTP headers |
| `method` | `string` | `'post'` | HTTP method |
| `name` | `string` | `'file'` | Form field name |
| `withCredentials` | `boolean` | `false` | Send cookies with upload |
| `directory` | `boolean` | `false` | Allow folder selection |
| `disabled` | `boolean` | `false` | Disable upload |
| `onChange` | `(info: UploadChangeParam) => void` | — | Fires at every stage |
| `onPreview` | `(file: UploadFile) => void` | — | Preview click |
| `onRemove` | `(file) => boolean \| Promise<boolean>` | — | Remove click; return `false` to prevent |
| `onDownload` | `(file) => void` | — | Download click |

### UploadFile type

```typescript
interface UploadFile<T = any> {
  uid: string;           // unique ID (required in controlled fileList)
  name: string;
  status?: 'error' | 'done' | 'uploading' | 'removed';
  percent?: number;
  url?: string;
  thumbUrl?: string;
  originFileObj?: File;  // raw File — undefined for server-initialized files
  response?: T;
}
```

### Patterns

```tsx
// Button upload
<Upload name="file" action="/api/upload" onChange={({ file, fileList }) => {
  if (file.status === 'done') message.success(`${file.name} uploaded`);
  if (file.status === 'error') message.error(`${file.name} failed`);
}}>
  <Button icon={<UploadOutlined />}>Upload</Button>
</Upload>

// Drag-and-drop
<Upload.Dragger name="files" multiple action="/api/upload"
  onChange={({ file }) => { if (file.status === 'done') message.success('Done!'); }}>
  <p className="ant-upload-drag-icon"><InboxOutlined /></p>
  <p className="ant-upload-text">Click or drag to upload</p>
</Upload.Dragger>

// Picture card with preview
<Upload listType="picture-card" fileList={fileList}
  onPreview={handlePreview} onChange={({ fileList }) => setFileList(fileList)}>
  {fileList.length >= 8 ? null : <div><PlusOutlined /><div>Upload</div></div>}
</Upload>

// Manual upload (beforeUpload returns false)
<Upload beforeUpload={(file) => { setFiles(f => [...f, file]); return false; }} fileList={fileList}>
  <Button>Select File</Button>
</Upload>
<Button onClick={doUpload}>Upload</Button>

// Validation: type + size check
const beforeUpload = (file: FileType) => {
  const ok = file.type === 'image/jpeg' || file.type === 'image/png';
  if (!ok) { message.error('JPG/PNG only!'); return Upload.LIST_IGNORE; }
  if (file.size / 1024 / 1024 > 2) { message.error('Max 2MB!'); return false; }
  return true;
};
```

### Common Mistakes
- **Controlled `fileList` requires manual update in `onChange`** — not updating freezes the list
- **`onChange` fires multiple times** per upload (select → progress ticks → done/error) — always check `file.status`
- **`beforeUpload` returning `false`** adds file in error state; **`Upload.LIST_IGNORE`** silently drops it — prefer the latter for avatar uploaders
- **`uid` must be unique and stable** in controlled `fileList` — duplicate UIDs break list behavior
- **`originFileObj` is undefined for server-initialized files** — guard before FileReader

---

## DatePicker

```typescript
import { DatePicker } from 'antd';
import type { DatePickerProps, RangePickerProps } from 'antd';
import dayjs from 'dayjs';
import type { Dayjs } from 'dayjs';
const { RangePicker } = DatePicker;
```

> **dayjs is required** — Ant Design v5 switched from moment.js. Install `dayjs` separately.

### DatePickerProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `Dayjs` | — | Controlled date |
| `defaultValue` | `Dayjs` | — | Initial date (uncontrolled) |
| `picker` | `'date' \| 'week' \| 'month' \| 'quarter' \| 'year'` | `'date'` | Selection granularity |
| `format` | `string \| ((v: Dayjs) => string)` | Depends on picker | Display format |
| `showTime` | `boolean \| TimePicker.Options` | — | Add time column |
| `disabledDate` | `(current: Dayjs, info) => boolean` | — | Restrict selectable dates |
| `disabledTime` | `(date: Dayjs) => { disabledHours?, ... }` | — | Restrict selectable times |
| `presets` | `{ label: ReactNode; value: Dayjs \| (() => Dayjs) }[]` | — | Quick-select shortcuts |
| `minDate` / `maxDate` | `Dayjs` | — | Date bounds (v5.14+) |
| `multiple` | `boolean` | `false` | Select multiple dates |
| `allowClear` | `boolean` | `true` | Show clear button |
| `disabled` | `boolean` | `false` | Disable picker |
| `inputReadOnly` | `boolean` | `false` | Calendar-only (no keyboard input) |
| `needConfirm` | `boolean` | — | Require OK button to confirm |
| `open` | `boolean` | — | Controlled open state |
| `status` | `'error' \| 'warning'` | — | Validation status |
| `variant` | `'outlined' \| 'borderless' \| 'filled' \| 'underlined'` | `'outlined'` | Visual style |
| `size` | `'large' \| 'middle' \| 'small'` | — | Input size |
| `onChange` | `(date: Dayjs \| null, dateString: string) => void` | — | Value change |
| `onOk` | `() => void` | — | OK button click (with showTime) |

**Default formats by picker:**

| picker | Format |
|--------|--------|
| `date` | `YYYY-MM-DD` |
| `week` | `YYYY-wo` |
| `month` | `YYYY-MM` |
| `quarter` | `YYYY-\QQ` |
| `year` | `YYYY` |
| with `showTime` | `YYYY-MM-DD HH:mm:ss` |

### RangePicker extras

| Prop | Type | Description |
|------|------|-------------|
| `value` | `[Dayjs, Dayjs]` | Controlled range |
| `presets` | `{ label, value: [Dayjs, Dayjs] }[]` | Preset ranges |
| `disabled` | `[boolean, boolean]` | Disable only start or end |
| `allowEmpty` | `[boolean, boolean]` | Allow unset start/end |
| `onCalendarChange` | `(dates, dateStrings, { range }) => void` | Fires after each side selected |
| `onChange` | `(dates, dateStrings) => void` | Fires when both sides selected |

### Patterns

```tsx
// All picker types
<DatePicker onChange={(date, str) => console.log(date, str)} />
<DatePicker picker="week" />
<DatePicker picker="month" />
<DatePicker picker="year" />

// With time
<DatePicker showTime onChange={(val, str) => console.log(str)} onOk={console.log} />

// Disable past dates
<DatePicker disabledDate={(d) => d && d < dayjs().startOf('day')} />

// Min/Max range constraint (v5.14+)
<DatePicker minDate={dayjs('2024-01-01')} maxDate={dayjs('2024-12-31')} />

// RangePicker with presets
const presets = [
  { label: 'Last 7 Days',  value: [dayjs().subtract(7, 'd'),  dayjs()] },
  { label: 'Last 30 Days', value: [dayjs().subtract(30, 'd'), dayjs()] },
];
<RangePicker presets={presets} onChange={(dates, strs) => console.log(strs)} />

// Disable future in range based on start
<RangePicker disabledDate={(current, { from }) =>
  from ? current > from.add(7, 'd') : false
} />
```

### Common Mistakes
- **`value` must be a `Dayjs` object** — not a string or `Date`; always wrap: `dayjs(myDate)`
- **`onChange` receives `null` when cleared** — always handle: `date && doSomething(date)`
- **`optionFilterProp` for search is set on Select** — for DatePicker, use `disabledDate`
- **RangePicker `onChange` fires only when both sides selected** — use `onCalendarChange` for intermediate state
- **`showTime` without `needConfirm`** auto-confirms when panel closes (even without OK)
- **`mode` prop vs `picker` prop** — don't use `mode` to set granularity; use `picker`

---

## Input

```typescript
import { Input } from 'antd';
import type { InputProps, InputRef, GetProps } from 'antd';
type OTPProps = GetProps<typeof Input.OTP>;
const { Search, TextArea, Password, OTP } = Input;
```

### InputProps

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `string` | — | Controlled value |
| `defaultValue` | `string` | — | Initial value (uncontrolled) |
| `prefix` | `ReactNode` | — | Left element inside input |
| `suffix` | `ReactNode` | — | Right element inside input |
| `allowClear` | `boolean \| { clearIcon? }` | `false` | Show clear button |
| `maxLength` | `number` | — | Hard character limit |
| `showCount` | `boolean \| function` | `false` | Show character counter |
| `count` | `CountConfig` | — | Advanced count config (v5.10+) |
| `disabled` | `boolean` | `false` | Disable input |
| `status` | `'error' \| 'warning'` | — | Validation status |
| `size` | `'large' \| 'middle' \| 'small'` | — | Input size |
| `variant` | `'outlined' \| 'borderless' \| 'filled' \| 'underlined'` | `'outlined'` | Visual style (v5.13+) |
| `type` | `string` | `'text'` | HTML input type |
| `id` | `string` | — | HTML id |
| `onChange` | `ChangeEventHandler<HTMLInputElement>` | — | Change handler |
| `onPressEnter` | `KeyboardEventHandler<HTMLInputElement>` | — | Enter key shorthand |
| `onClear` | `() => void` | — | Clear button click (v5.20+) |

### Instance ref (InputRef)

```typescript
const ref = useRef<InputRef>(null);
ref.current?.focus();
ref.current?.blur();
ref.current?.select();
ref.current?.setSelectionRange(0, 5);
ref.current?.input; // raw HTMLInputElement
```

### Sub-components

**`Input.TextArea`** — adds:
- `autoSize?: boolean | { minRows?, maxRows? }` — auto-grow height
- `rows`, `cols`, `wrap` — standard textarea attrs

**`Input.Search`** — adds:
- `enterButton?: boolean | ReactNode` — show search button
- `loading?: boolean` — loading state on button
- `onSearch: (value, event, { source }) => void` — fires on Enter or button click

**`Input.Password`** — adds:
- `visibilityToggle?: boolean | { visible?, onVisibleChange? }` — show/hide toggle
- `iconRender?: (visible) => ReactNode` — custom eye icon

**`Input.OTP`** (v5.16+):
- `length?: number` — number of cells (default 6)
- `mask?: boolean | string` — mask cells
- `formatter?: (value: string) => string` — transform display
- `separator?: ReactNode | ((index) => ReactNode)` — between cells
- `onChange?: (value: string) => void`

> **`Input.Group` is deprecated** — use `Space.Compact` instead.

### Patterns

```tsx
// Basic with prefix/suffix
<Input prefix={<UserOutlined />} suffix={<InfoCircleOutlined />}
  placeholder="Username" allowClear />

// Variants
<Input variant="borderless" placeholder="Borderless" />
<Input variant="filled" placeholder="Filled" />
<Input status="error" placeholder="Error state" />

// TextArea with auto-resize
<Input.TextArea autoSize={{ minRows: 2, maxRows: 6 }} showCount maxLength={200} />

// Search
<Input.Search placeholder="Search..." enterButton="Search" size="large"
  onSearch={(val, _e, { source }) => source !== 'clear' && fetchResults(val)} />

// Password with external control
const [visible, setVisible] = useState(false);
<Input.Password visibilityToggle={{ visible, onVisibleChange: setVisible }} />

// OTP
<Input.OTP length={6} onChange={(val) => console.log(val)}
  formatter={(s) => s.toUpperCase()} />

// Ref focus
const ref = useRef<InputRef>(null);
<Input ref={ref} />
<Button onClick={() => ref.current?.focus()}>Focus</Button>

// Unicode-safe character count
<Input count={{
  show: true, max: 50,
  strategy: (txt) => [...txt].length,  // counts code points, not UTF-16 units
  exceedFormatter: (txt, { max }) => [...txt].slice(0, max).join(''),
}} />

// Space.Compact replaces deprecated Input.Group
<Space.Compact>
  <Input defaultValue="https://" style={{ width: '30%' }} />
  <Input placeholder="domain.com" style={{ width: '70%' }} />
</Space.Compact>
```

### Common Mistakes
- **`Input.Group` is deprecated** — use `Space.Compact`
- **`addonBefore`/`addonAfter` are deprecated** — use `Space.Compact` with `Space.Addon`
- **`showCount` only shows counter UI; `maxLength` enforces the limit** — they're independent
- **`autoSize` on TextArea causes synchronous reflow** — set `maxRows` to bound layout jumping
- **Search `onSearch` source field**: `'input'` = Enter key, `'suffix'` = button click, `'clear'` = clear button
- **Default `count.strategy` uses `.length`** which counts UTF-16 units — emoji counts as 2; use `[...txt].length` for Unicode safety

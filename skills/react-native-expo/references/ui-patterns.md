# UI Patterns — Forms, Bottom Sheets, Components

## Forms — react-hook-form + zod

### Schema + Hook

```typescript
import { z } from "zod"
import { useForm, Controller } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"

const createItemSchema = z.object({
  name: z.string().min(1, "Name is required").max(100),
  category: z.string().min(1, "Category is required"),
  brand: z.string().optional(),
  notes: z.string().max(500).optional(),
})

type CreateItemForm = z.infer<typeof createItemSchema>

const useItemForm = (defaults?: Partial<CreateItemForm>) =>
  useForm<CreateItemForm>({
    resolver: zodResolver(createItemSchema),
    defaultValues: { name: "", category: "", brand: "", ...defaults },
  })
```

### Form Component

```typescript
const ItemForm = () => {
  const { control, handleSubmit, formState: { errors } } = useItemForm()
  const { mutate: createItem, isPending } = useCreateItem()

  return (
    <View>
      <Controller
        control={control}
        name="name"
        render={({ field: { onChange, onBlur, value } }) => (
          <TextInput
            placeholder="Item name"
            onChangeText={onChange}     // onChangeText, NOT onChange
            onBlur={onBlur}
            value={value}
          />
        )}
      />
      {errors.name && (
        <Typography variant="b3" color={Theme.color.error}>
          {errors.name.message}
        </Typography>
      )}
      <Button title="Save" onPress={handleSubmit((d) => createItem(d))} loading={isPending} />
    </View>
  )
}
```

### React Native Specifics

- Use `onChangeText` not `onChange` for TextInput
- Use `Controller` wrapper (RN doesn't support `ref` registration)
- Stick with **zod v3** syntax — v4 has RN compatibility issues
- Memoize `onSubmit` with `useCallback` for list forms

## Bottom Sheet — @gorhom/bottom-sheet v5

### Basic Usage

```typescript
import BottomSheet, { BottomSheetView, BottomSheetBackdrop } from "@gorhom/bottom-sheet"

const MySheet = () => {
  const ref = useRef<BottomSheet>(null)
  const snapPoints = useMemo(() => ["25%", "50%", "90%"], [])

  return (
    <BottomSheet
      ref={ref}
      snapPoints={snapPoints}
      enableDynamicSizing={false}   // Disable when using fixed snap points
      enablePanDownToClose
      index={-1}                     // Start closed
      backdropComponent={BottomSheetBackdrop}
    >
      <BottomSheetView>{/* Content */}</BottomSheetView>
    </BottomSheet>
  )
}
```

### With Scrollable Content

```typescript
import { BottomSheetScrollView, BottomSheetFlashList } from "@gorhom/bottom-sheet"

// ScrollView
<BottomSheet snapPoints={["50%", "90%"]}>
  <BottomSheetScrollView>{/* content */}</BottomSheetScrollView>
</BottomSheet>

// FlashList
<BottomSheet snapPoints={["50%", "90%"]}>
  <BottomSheetFlashList data={items} renderItem={renderItem} estimatedItemSize={60} />
</BottomSheet>
```

### Dynamic Sizing (v5 default)

v5 enables dynamic sizing by default. Disable for fixed snap points or limit height:
```typescript
<BottomSheet enableDynamicSizing={false} snapPoints={["50%"]} />
<BottomSheet enableDynamicSizing maxDynamicContentSize={500} />
```

### ⚠️ CRITICAL: Dynamic Sizing + Scrollable Content

**NEVER** use `enableDynamicSizing={true}` with `BottomSheetScrollView` or `BottomSheetFlashList`.
Dynamic sizing measures children's intrinsic height via `BottomSheetView`, but scrollable content
has no fixed intrinsic height → sheet appears truncated (header-only).

```typescript
// ❌ WRONG — sheet will appear truncated, only showing header
<BottomSheetWrapper ref={ref} name="my-sheet">
  <BottomSheetScrollView>{/* list content */}</BottomSheetScrollView>
</BottomSheetWrapper>

// ✅ CORRECT — disable dynamic sizing, use explicit snap points
const snapPoints = useMemo(() => ["50%"], [])

<BottomSheetWrapper ref={ref} name="my-sheet" enableDynamicSizing={false} snapPoints={snapPoints}>
  <BottomSheetScrollView>{/* list content */}</BottomSheetScrollView>
</BottomSheetWrapper>
```

The app's `BottomSheetWrapper` defaults to `enableDynamicSizing={true}`. Always override when content is scrollable.

### BottomSheetWrapper (App Component)

Located at `@/shared/components/bottom-sheet`. Wraps `@gorhom/bottom-sheet` BottomSheetModal with:
- Auto safe-area bottom padding
- Header component (title + close button + drag handle)
- Backdrop with 0.5 opacity
- Patched `present()` that always cleans up first (no stuck states)

```typescript
import { BottomSheetModal } from "@gorhom/bottom-sheet"
import { BottomSheetWrapper } from "@/shared/components/bottom-sheet"

const ref = useRef<BottomSheetModal>(null)
const snapPoints = useMemo(() => ["50%"], [])

<BottomSheetWrapper
  ref={ref}
  name="my-sheet"
  enableDynamicSizing={false}
  snapPoints={snapPoints}
  header={{
    title: "Sheet Title",
    showCloseButton: true,
    closeButtonText: "Cancel",
  }}
  onDismiss={() => setSheetOpen(false)}
>
  {/* Content */}
</BottomSheetWrapper>

// Open: ref.current?.present()
// Close: ref.current?.dismiss()
```

## Shared Components

### Typography

```typescript
import { Typography } from "@/shared/components"

<Typography variant="h1">Title</Typography>
<Typography variant="b2" color={Theme.color.textSecondary}>Body</Typography>
<Typography variant="b3" numberOfLines={2}>Truncated</Typography>
```

### Button

```typescript
import { Button } from "@/shared/components"

// Variants: primary (brand+shadow), secondary (neutral), outline, ghost, danger
// Sizes: small (36px), medium (44px), large (52px)
<Button title="Save" variant="primary" onPress={handlePress} loading={isPending} />
<Button title="Cancel" variant="secondary" onPress={handleCancel} />
<Button title="Delete" variant="danger" onPress={handleDelete} />
```

### Image (expo-image)

```typescript
import { Image } from "expo-image"

<Image
  source={{ uri: imageUrl }}
  style={{ width: 120, height: 120, borderRadius: Spacing.sm }}
  contentFit="cover"
  transition={200}
  cachePolicy="memory-disk"
  recyclingKey={item._id}   // Important in lists
/>
```

### Loading Skeletons

```typescript
import { Shimmer } from "@/shared/components"

{isLoading ? (
  <Shimmer width={200} height={20} borderRadius={4} />
) : (
  <Typography variant="b1">{data.name}</Typography>
)}
```

Platform-specific: `shimmer.ios.tsx` / `shimmer.android.tsx`

### Toast Messages

```typescript
import { showSuccessToast, showErrorToast } from "@/shared/components/toast"

showSuccessToast("Success", "Item saved successfully")
showErrorToast("Error", "Failed to save item")
```

### Dialogs

```typescript
// Pattern: Zustand store controls dialog visibility
const { isOpen, open, close } = useDialogStore(
  useShallow((s) => ({ isOpen: s.isOpen, open: s.open, close: s.close }))
)

<Dialog visible={isOpen} onDismiss={close}>
  <Dialog.Title>Confirm</Dialog.Title>
  <Dialog.Content><Typography variant="b1">Are you sure?</Typography></Dialog.Content>
  <Dialog.Actions>
    <Button title="Cancel" variant="secondary" onPress={close} />
    <Button title="Delete" variant="danger" onPress={handleDelete} />
  </Dialog.Actions>
</Dialog>
```

### Glass Morphism Components

Available in `@/shared/components/`: `GlassCard`, `GlassButton`, `GlassInput`

## Keyboard Handling

```typescript
import { KeyboardAwareScrollView } from "react-native-keyboard-controller"

<KeyboardAwareScrollView>{/* Form content */}</KeyboardAwareScrollView>
```

## Image Picking & Compression

```typescript
import * as ImagePicker from "expo-image-picker"
import { compressImage } from "@/shared/utils/compress-image"

const result = await ImagePicker.launchImageLibraryAsync({
  mediaTypes: ImagePicker.MediaTypeOptions.Images,
  quality: 0.8,
  allowsEditing: true,
  aspect: [1, 1],
})
if (!result.canceled) {
  const compressed = await compressImage(result.assets[0].uri)
}
```

## Calendar

```typescript
import { Calendar } from "@marceloterreiro/flash-calendar"

<Calendar
  calendarActiveDateRanges={activeDateRanges}
  onCalendarDayPress={handleDayPress}
/>
```

## Popover

```typescript
import Popover from "react-native-popover-view"

<Popover from={<TouchableOpacity><Icon name="more" /></TouchableOpacity>}>
  {/* Menu content */}
</Popover>
```

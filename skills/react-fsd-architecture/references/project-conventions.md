# Project Conventions — FSD Implementation

This project's specific folder structure, naming conventions, and coding rules for applying Feature-Sliced Design.

---

## Folder Structure

```
src/
├── app/
│   ├── api/                            # API routes
│   │   └── health/
│   │       └── route.ts
│   ├── dashboard/                      # Dashboard section
│   │   └── (main)/                     # Main route group
│   │       ├── personal-access-token/
│   │       └── quan-ly/                # Management
│   │           ├── layout.tsx
│   │           └── page.tsx
│   ├── landing/                        # Landing pages
│   │   ├── auth/
│   │   ├── pending-activation/
│   │   ├── layout.tsx
│   │   └── page.tsx
│   ├── not-found/
│   │   └── page.tsx
│   ├── layout.tsx
│   ├── page.tsx
│   └── favicon.ico
│
├── entities/                           # Backend data models
│   └── user/                           # Example entity
│       ├── _apis/                      # API calling endpoint logic
│       │   ├── get-list-users.api.ts
│       │   ├── add-user.api.ts
│       │   └── update-user.api.ts
│       ├── _types/                     # API type response
│       │   └── user.type.ts
│       └── _utils/                     # Shared utilities
│           ├── get-user-entity-status.ts
│           ├── get-user-role-name.ts
│           └── user-enum.util.ts
│
├── features/                           # Feature modules
│   └── user/                           # Example feature
│       ├── _store/                     # Feature-specific stores
│       │   └── user-dialog.store.ts
│       ├── _ui/                        # Shared UI within feature
│       │   └── user-dialogs.tsx
│       ├── add-user/                   # Add user action
│       ├── delete-user/                # Delete user action
│       ├── invite-user/                # Invite user action
│       └── list-users/                 # List users view
│
└── shared/                             # Shared resources
    ├── _components/                    # Shared UI components
    ├── _config/                        # App configuration
    ├── _constants/                     # Constants and enums
    ├── _hooks/                         # Custom React hooks
    ├── _libs/                          # Third-party library wrappers
    ├── _providers/                     # React context providers
    ├── _stores/                        # Global Zustand stores
    ├── _types/                         # Shared TypeScript types
    │   ├── api.error.ts
    │   ├── entity-status-enum.ts
    │   ├── id-and-timestamps.ts
    │   ├── pagination.ts
    │   └── sort-by-order.enum.ts
    └── _utils/                         # Utility functions
```

### Segment naming convention

All segments use **underscore prefix** (`_apis/`, `_types/`, `_utils/`, `_store/`, `_ui/`) to distinguish them from action sub-folders.

| Segment | Contains |
|---|---|
| `_apis/` | React Query hooks (API calls) |
| `_types/` | TypeScript interfaces / response types |
| `_utils/` | Enums, helper functions |
| `_store/` | Zustand stores (feature-scoped) |
| `_ui/` | Shared UI components within the feature |

---

## API Naming Convention

```
[action]-[entity].api.ts
```

```
get-list-users.api.ts   → Get list of users
add-user.api.ts         → Add new user
update-user.api.ts      → Update user
delete-user.api.ts      → Delete user
```

---

## Type Naming Convention

```
[Entity]Res
```

Always extend with `& IdAndTimeStamps`:

```typescript
import { IdAndTimeStamps } from '@/shared/_types/id-and-timestamps';

export enum UserRole {
  SUPER_ADMIN = 'super_admin',
  CLASS_ADMIN = 'class_admin',
  STUDENT = 'student',
}

export enum UserStatus {
  ACTIVE = 'active',
  DISABLED = 'disabled',
  BANNED = 'banned',
  PENDING_DELETION = 'pending_deletion',
  DELETED = 'deleted',
}

export type UserRes = {
  name?: string;
  email: string;
  roles?: UserRole[];
  status: UserStatus;
} & IdAndTimeStamps;
```

### Derived types

```typescript
// With populated references
export type UserResWithPopulatedClasses = Omit<UserRes, 'managed_classes'> & {
  managed_classes?: ManagedClass[];
};

// Partial type for specific use cases
export type UserBasicInfo = Pick<UserRes, '_id' | 'name' | 'email' | 'avatar'>;
```

---

## Coding Rules

### 1. Always organize code into proper folders

```
// ❌ Don't write everything in one file
// ✅ Split code into appropriate folders based on responsibility
```

### 2. Reuse entity types — don't create redundant types

```typescript
// ❌ Bad - Creating redundant types
type AddUserFormData = {
  name: string;
  email: string;
  role: string;
};

// ✅ Good - Reuse from entity
import { UserRes, UserRole } from '@/entities/user/_types/user.type';

type AddUserFormData = Pick<UserRes, 'name' | 'email'> & {
  role: UserRole;
};
```

### 3. Create separate types for populated data

```typescript
// In entity _types/user.type.ts

// Base type (references are IDs)
export type UserRes = {
  name: string;
  email: string;
  managed_classes?: string[]; // Array of class IDs
} & IdAndTimeStamps;

// Populated type (references are objects)
export type ManagedClass = {
  _id: string;
  name: string;
};

export type UserResWithPopulatedClasses = Omit<UserRes, 'managed_classes'> & {
  managed_classes?: ManagedClass[];
};
```

```typescript
// In feature component — import the correct populated type
import { UserResWithPopulatedClasses } from '@/entities/user/_types/user.type';

function UserCard({ user }: { user: UserResWithPopulatedClasses }) {
  return (
    <div>
      <h3>{user.name}</h3>
      {user.managed_classes?.map((cls) => (
        <span key={cls._id}>{cls.name}</span>
      ))}
    </div>
  );
}
```

### 4. Import from entity, not recreate

```typescript
// ❌ Bad - Recreating enums
const UserStatus = {
  ACTIVE: 'active',
  DISABLED: 'disabled',
};

// ✅ Good - Import from entity
import { UserStatus } from '@/entities/user/_types/user.type';
```

### 5. Ask for missing types — don't create them

If a type is missing: ask first to confirm where it should be defined. Don't create types without checking.

### 6. Keep logic in the correct place

```typescript
// ❌ Bad - Logic inside component
function UserList() {
  const formatUserStatus = (status: UserStatus) => {
    switch (status) {
      case UserStatus.ACTIVE: return 'Hoạt động';
      case UserStatus.DISABLED: return 'Vô hiệu hóa';
      default: return 'Không xác định';
    }
  };
  return <div>{formatUserStatus(user.status)}</div>;
}

// ✅ Good - Logic in entity _utils
// entities/user/_utils/get-user-status-text.ts
export function getUserStatusText(status: UserStatus): string {
  switch (status) {
    case UserStatus.ACTIVE: return 'Hoạt động';
    case UserStatus.DISABLED: return 'Vô hiệu hóa';
    default: return 'Không xác định';
  }
}

// Then import in component
import { getUserStatusText } from '@/entities/user/_utils/get-user-status-text';

function UserList() {
  return <div>{getUserStatusText(user.status)}</div>;
}
```

### 7. Understand scope: shared vs scoped

```
src/
├── shared/                         # ✅ Global - use anywhere
│   └── _utils/
│       └── format-date.ts          # Can use in any entity/feature
│
├── entities/
│   └── user/
│       └── _utils/                 # ⚠️ Scoped to user entity only
│           └── get-user-status.ts  # Only use within user entity
│
└── features/
    └── user/
        └── _hooks/                 # ⚠️ Scoped to user feature only
            └── use-user-form.ts    # Only use within user feature
```

**Rule of thumb:**
- Need it in multiple entities/features? → Put in `shared/`
- Only need it in one entity? → Put in `entities/[entity]/_utils/`
- Only need it in one feature? → Put in `features/[feature]/_utils/`

# Advanced Mongoose Patterns

Detailed reference for advanced patterns beyond the main SKILL.md. Load this when working on specific advanced scenarios.

## Pre/Post Hooks (Middleware)

### Pre-save: Hash Password

```typescript
UserSchema.pre<UserDocument>('save', async function (next) {
  if (!this.isModified('password')) return next()
  this.password = await bcrypt.hash(this.password, 12)
  next()
})
```

### Pre-find: Auto-exclude soft-deleted

```typescript
ProductSchema.pre('find', function () {
  this.where({ deletedAt: null })
})

ProductSchema.pre('findOne', function () {
  this.where({ deletedAt: null })
})

ProductSchema.pre('countDocuments', function () {
  this.where({ deletedAt: null })
})
```

### Post-save: Side Effects

```typescript
OrderSchema.post<OrderDocument>('save', async function (doc) {
  // Send notification after order created
  await notificationService.send(doc.userId, `Order ${doc._id} placed`)
})
```

### Hook Gotchas

- `findOneAndUpdate` does NOT trigger `save` hooks — use `pre('findOneAndUpdate')` instead
- `insertMany` does NOT trigger `save` hooks — use `pre('insertMany')` if needed
- Arrow functions lose `this` context — always use `function` keyword in hooks

## Custom Methods & Statics

### Instance Methods

```typescript
// Schema definition
UserSchema.methods.comparePassword = async function (candidate: string): Promise<boolean> {
  return bcrypt.compare(candidate, this.password)
}

UserSchema.methods.toPublicJSON = function () {
  const { password, __v, ...rest } = this.toObject()
  return rest
}

// Usage
const user = await User.findOne({ email })
const isValid = await user.comparePassword(inputPassword)
```

### Static Methods

```typescript
// Schema definition
UserSchema.statics.findByEmail = function (email: string) {
  return this.findOne({ email: email.toLowerCase() }).lean()
}

UserSchema.statics.findActiveByOrg = function (orgId: string) {
  return this.find({ organization: orgId, status: 'active' }).lean()
}

// Usage
const user = await User.findByEmail('john@example.com')
```

### TypeScript Typing for Methods/Statics

```typescript
// Define interfaces
interface IUserMethods {
  comparePassword(candidate: string): Promise<boolean>
  toPublicJSON(): Omit<User, 'password'>
}

interface UserModel extends Model<User, {}, IUserMethods> {
  findByEmail(email: string): Promise<User | null>
  findActiveByOrg(orgId: string): Promise<User[]>
}

// In NestJS module
@InjectModel(User.name) private userModel: UserModel
```

## Mongoose Plugins

### Global Plugins

```typescript
// Apply to all schemas
import mongooseLeanVirtuals from 'mongoose-lean-virtuals'
import mongooseLeanGetters from 'mongoose-lean-getters'

mongoose.plugin(mongooseLeanVirtuals)
mongoose.plugin(mongooseLeanGetters)
```

### Soft Delete Plugin

```typescript
function softDeletePlugin(schema: Schema) {
  schema.add({ deletedAt: { type: Date, default: null } })

  schema.methods.softDelete = function () {
    this.deletedAt = new Date()
    return this.save()
  }

  schema.methods.restore = function () {
    this.deletedAt = null
    return this.save()
  }

  // Auto-filter soft-deleted docs
  schema.pre('find', function () { this.where({ deletedAt: null }) })
  schema.pre('findOne', function () { this.where({ deletedAt: null }) })
  schema.pre('countDocuments', function () { this.where({ deletedAt: null }) })

  // Index for queries that include deleted docs
  schema.index({ deletedAt: 1 })
}

// Apply
UserSchema.plugin(softDeletePlugin)
```

### Pagination Plugin

```typescript
interface PaginateResult<T> {
  docs: T[]
  totalDocs: number
  page: number
  totalPages: number
  hasNextPage: boolean
  hasPrevPage: boolean
}

function paginatePlugin(schema: Schema) {
  schema.statics.paginate = async function (
    filter: FilterQuery<any> = {},
    options: { page?: number; limit?: number; sort?: any; select?: string; lean?: boolean } = {},
  ): Promise<PaginateResult<any>> {
    const page = Math.max(1, options.page || 1)
    const limit = Math.min(100, Math.max(1, options.limit || 20))
    const skip = (page - 1) * limit

    const [docs, totalDocs] = await Promise.all([
      this.find(filter)
        .sort(options.sort || { createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select(options.select || '')
        .lean(options.lean ?? true)
        .exec(),
      this.countDocuments(filter),
    ])

    const totalPages = Math.ceil(totalDocs / limit)
    return {
      docs,
      totalDocs,
      page,
      totalPages,
      hasNextPage: page < totalPages,
      hasPrevPage: page > 1,
    }
  }
}
```

## Change Streams

Watch real-time changes to a collection (requires replica set).

```typescript
// Watch for new orders
const changeStream = this.orderModel.watch([
  { $match: { operationType: 'insert' } },
])

changeStream.on('change', (change) => {
  console.log('New order:', change.fullDocument)
  // Trigger notifications, update dashboards, etc.
})

// Watch for specific field updates
const priceStream = this.productModel.watch([
  { $match: { 'updateDescription.updatedFields.price': { $exists: true } } },
])

// Cleanup
process.on('SIGTERM', () => changeStream.close())
```

### Resume After Disconnect

```typescript
let resumeToken: unknown

const stream = this.orderModel.watch([], {
  fullDocument: 'updateLookup',  // include full doc on updates
  ...(resumeToken ? { resumeAfter: resumeToken } : {}),
})

stream.on('change', (change) => {
  resumeToken = change._id  // save for resume
  handleChange(change)
})

stream.on('error', (err) => {
  logger.error('Change stream error:', err)
  // Reconnect with resumeToken after delay
  setTimeout(() => startChangeStream(), 5000)
})
```

## Cursor-Based Streaming

Process large datasets without loading everything into memory.

```typescript
// Process 1M documents with constant memory usage
const cursor = this.userModel.find({ status: 'active' }).lean().cursor()

for await (const user of cursor) {
  await processUser(user)
}

// Or with batch size control
const cursor = this.orderModel.find().lean().cursor({ batchSize: 100 })
```

## Schema Versioning

Handle schema evolution in existing data.

```typescript
@Schema({ timestamps: true })
export class User {
  @Prop({ default: 2 })
  schemaVersion: number

  @Prop({ required: true })
  name: string

  // v2: contact methods as array (replaces v1 phone/email fields)
  @Prop({ type: [{ type: String, value: String }], default: [] })
  contactMethods: Array<{ type: string; value: string }>
}

// Migration on read
async findUser(id: string) {
  const doc = await this.userModel.findById(id)
  if (!doc.schemaVersion || doc.schemaVersion < 2) {
    return this.migrateToV2(doc)
  }
  return doc.toObject()
}
```

## Multi-Tenant Patterns

### Database-per-Tenant

```typescript
const connectionMap = new Map<string, mongoose.Connection>()

async getTenantConnection(tenantId: string): Promise<mongoose.Connection> {
  if (connectionMap.has(tenantId)) return connectionMap.get(tenantId)!

  const conn = await mongoose.createConnection(`${baseUri}/${tenantId}`, {
    maxPoolSize: 5,
  })
  connectionMap.set(tenantId, conn)
  return conn
}

// Get model for tenant
async getTenantModel<T>(tenantId: string, name: string, schema: Schema): Promise<Model<T>> {
  const conn = await this.getTenantConnection(tenantId)
  return conn.model<T>(name, schema)
}
```

### Collection-per-Tenant (simpler, same database)

```typescript
async getTenantModel(tenantId: string) {
  return this.connection.model('Order', OrderSchema, `orders_${tenantId}`)
}
```

### Shared Collection with Tenant Field

```typescript
@Schema({ timestamps: true })
export class Order {
  @Prop({ required: true, index: true })
  tenantId: string

  // ... other fields
}

// Always include tenantId in queries
OrderSchema.index({ tenantId: 1, createdAt: -1 })
```

## Explain & Debug

### Analyze Query Performance

```typescript
// In development only
const explanation = await this.userModel
  .find({ email: 'test@example.com' })
  .explain('executionStats')

// Key metrics:
// executionStats.totalDocsExamined — docs scanned (lower is better)
// executionStats.totalKeysExamined — index keys scanned
// executionStats.executionTimeMillis — query time
// winningPlan.stage — IXSCAN (good) vs COLLSCAN (bad)
```

### Enable Mongoose Debug Logging

```typescript
// Log all queries in development
mongoose.set('debug', true)

// Custom logger
mongoose.set('debug', (collectionName, method, query, doc) => {
  logger.debug(`${collectionName}.${method}`, JSON.stringify(query))
})
```

### Monitor Connection Pool

```typescript
const pool = mongoose.connection.getClient().options
// Check: pool.maxPoolSize, pool.minPoolSize

// Monitor pool events
mongoose.connection.getClient().on('connectionPoolCreated', (event) => {
  logger.debug('Pool created:', event)
})
mongoose.connection.getClient().on('connectionCheckedOut', (event) => {
  logger.debug('Connection checked out:', event)
})
```

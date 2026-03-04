---
name: mongodb
description: |
  **MongoDB & Mongoose Best Practices**: Production patterns for schema design, indexing, aggregation pipelines, transactions, connection management, and common pitfalls — with NestJS/Mongoose focus.
  - MANDATORY TRIGGERS: mongodb, mongoose, mongo, schema design, embedding vs referencing, compound index, aggregation pipeline, $lookup, $match, $group, populate, lean, mongoose query, nosql, mongodb performance, mongodb index, mongodb transaction, mongoose schema, mongoose plugin, mongoose virtual, mongoose discriminator, bucket pattern, outlier pattern, computed pattern, subset pattern, mongodb connection pool, mongodb replica set, insertMany, bulkWrite, mongodb atlas
  - Use this skill whenever the user is designing MongoDB schemas, writing Mongoose queries, building aggregation pipelines, debugging MongoDB performance, or reviewing MongoDB/Mongoose code. Also trigger when discussing data modeling patterns, index optimization, transaction safety, or connection tuning.
---

# MongoDB & Mongoose — Best Practices & Patterns

Production-ready patterns for MongoDB 7+ and Mongoose 8+ with NestJS. Covers schema design, indexing strategy, aggregation pipelines, transactions, connection management, and common anti-patterns.

## Core Mental Model

**MongoDB is not a relational database with JSON syntax.** Model your data to match how your application reads and writes it — not how you would normalize tables. The biggest performance wins (and losses) happen at the schema design stage, not at query time.

Key implications:
- Embedding is the default; reference only when you have a reason
- Reads are fast when the working set fits in RAM — keep documents lean
- Every index speeds reads but slows writes — be deliberate
- Aggregation pipelines are your SQL replacement — learn the stage ordering

## Schema Design: Embedding vs Referencing

### Decision Framework

| Situation | Strategy | Why |
|-----------|----------|-----|
| Data always accessed together, bounded size | **Embed** | Single read, atomic writes |
| Data accessed independently or shared | **Reference** | Avoids duplication, separate lifecycle |
| Read-heavy, rarely-updated child field | **Denormalize** (copy field) | Eliminates join on hot path |
| > ~100 items on "many" side | **Reference array** | Array growth impacts performance |
| > ~thousands on "many" side | **Parent reference** (child stores parent ID) | Unbounded arrays hit 16MB limit |

### One-to-Few: Embed

```typescript
// Addresses on a user — bounded, always fetched together
@Schema({ timestamps: true })
export class User {
  @Prop({ required: true })
  name: string

  @Prop({
    type: [{
      street: String,
      city: String,
      zipCode: String,
      isDefault: { type: Boolean, default: false },
    }],
    default: [],
  })
  addresses: Array<{ street: string; city: string; zipCode: string; isDefault: boolean }>
}
```

### One-to-Many: Reference Array

```typescript
// Product has parts — parts are accessed independently, shared across products
@Schema({ timestamps: true })
export class Product {
  @Prop({ required: true })
  name: string

  @Prop({ type: [{ type: Types.ObjectId, ref: 'Part' }], default: [] })
  parts: Types.ObjectId[]  // bounded — a product has ~10-50 parts
}
```

### One-to-Squillions: Parent Reference

```typescript
// Log messages for a host — unbounded, query from child side
@Schema({ timestamps: true })
export class LogMessage {
  @Prop({ required: true })
  message: string

  @Prop({ type: Types.ObjectId, ref: 'Host', required: true, index: true })
  host: Types.ObjectId  // child stores parent reference
}

// Query: find recent logs for a host
await this.logModel.find({ host: hostId }).sort({ createdAt: -1 }).limit(100).lean()
```

### Extended Reference (Denormalize for Display)

```typescript
// Order embeds frequently-read customer fields to avoid $lookup
@Schema({ timestamps: true })
export class Order {
  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  userId: Types.ObjectId

  // Denormalized for display — avoids populate on order list
  @Prop({ type: { name: String, email: String } })
  customer: { name: string; email: string }

  @Prop({ required: true })
  total: number
}
// Trade-off: update denormalized copy when user name/email changes
```

## Indexing Strategy

### The ESR Rule: Equality → Sort → Range

Order compound index fields as **E**quality, **S**ort, **R**ange — this is the single most important indexing principle.

```typescript
// Query: active orders, sorted by date, amount in range
// db.orders.find({ status: 'active', amount: { $gte: 100 } }).sort({ createdAt: -1 })

// CORRECT — ESR order:
OrderSchema.index({ status: 1, createdAt: -1, amount: 1 })
//                  ^Equality   ^Sort           ^Range

// WRONG — range before sort causes in-memory sort:
OrderSchema.index({ status: 1, amount: 1, createdAt: -1 })
```

**Why:** Equality narrows the dataset. Sort fields served from index (no blocking sort). Range breaks sort ordering, so it must trail.

### Covered Queries

A query answered entirely from the index — `totalDocsExamined: 0` in explain.

```typescript
// Index covers all query + sort + projection fields
UserSchema.index({ email: 1, status: 1, firstName: 1, lastName: 1 })

// Covered query — _id must be explicitly excluded
await this.userModel
  .find({ email: 'test@example.com', status: 'active' })
  .select({ _id: 0, firstName: 1, lastName: 1 })
  .lean()
```

### Partial Indexes

Index only documents matching a filter — smaller index, faster writes.

```typescript
// Index only active orders — much smaller than full index
OrderSchema.index(
  { customerId: 1, createdAt: -1 },
  { partialFilterExpression: { status: 'active' } }
)

// Index only where field exists
UserSchema.index(
  { phoneNumber: 1 },
  { partialFilterExpression: { phoneNumber: { $exists: true } } }
)
```

### TTL Indexes (Auto-Delete)

```typescript
// Sessions expire 24 hours after creation
@Prop({ type: Date, default: Date.now, expires: '24h' })
createdAt: Date
// Mongoose handles creating the TTL index from `expires`
```

### Text Indexes

```typescript
// Full-text search with field weights
ArticleSchema.index(
  { title: 'text', body: 'text', tags: 'text' },
  { weights: { title: 10, tags: 5, body: 1 } }
)

// Search
await this.articleModel
  .find({ $text: { $search: 'mongodb performance' } })
  .select({ score: { $meta: 'textScore' } })
  .sort({ score: { $meta: 'textScore' } })
  .lean()
```

> For production full-text search, prefer MongoDB Atlas Search (Lucene-backed) — supports fuzzy matching, synonyms, autocomplete, and facets.

### Case-Insensitive Queries

```typescript
// BAD: regex disables index (or causes IXSCAN with slow regex)
await this.userModel.find({ email: /^john@example\.com$/i })

// GOOD: collation-based case-insensitive index
UserSchema.index({ email: 1 }, { collation: { locale: 'en', strength: 2 } })

await this.userModel
  .find({ email: 'John@Example.Com' })
  .collation({ locale: 'en', strength: 2 })
  .lean()
```

### Index Hygiene Rules

1. **Never index low-cardinality booleans alone** — `isActive: 1` is useless alone (50% selectivity). Use as part of a compound index.
2. **Audit unused indexes** — `db.collection.aggregate([{ $indexStats: {} }])`. Each index slows every write.
3. **Every write updates every covering index** — more indexes = slower writes.
4. **Working set must fit in RAM** — if indexes exceed available RAM, performance collapses.

## Aggregation Pipelines

### Golden Rule: Filter Early, Reshape Early, Join Late

```typescript
// ANTI-PATTERN: $lookup before $match
const result = await this.orderModel.aggregate([
  { $lookup: { from: 'users', localField: 'userId', foreignField: '_id', as: 'user' } },
  { $match: { status: 'shipped' } },  // too late — joined everything first
])

// CORRECT: $match first, $project to trim, $lookup last
const result = await this.orderModel.aggregate([
  // 1. Filter first — uses index
  { $match: { status: 'shipped', createdAt: { $gte: startDate } } },

  // 2. Project only needed fields
  { $project: { userId: 1, total: 1, items: 1 } },

  // 3. Group before lookup if applicable
  { $group: { _id: '$userId', orderCount: { $sum: 1 }, revenue: { $sum: '$total' } } },

  // 4. Join AFTER reducing the dataset
  { $lookup: { from: 'users', localField: '_id', foreignField: '_id', as: 'user' } },
  { $unwind: '$user' },

  // 5. Final projection
  { $project: { 'user.password': 0 } },
])
```

### Stage Order Cheat Sheet

| Priority | Stage | Reason |
|----------|-------|--------|
| 1st | `$match` | Hit the index, reduce document count |
| 2nd | `$sort` + `$limit` | Use index for sort; limit early |
| 3rd | `$project` / `$addFields` | Reduce document size flowing through pipeline |
| 4th | `$group` | Aggregate the reduced set |
| Last | `$lookup` | Join only surviving documents |

### Index Usage in Aggregation

MongoDB uses indexes **only** in `$match` and `$sort` at the **beginning** of the pipeline. Once `$group`, `$lookup`, or reshaping stages appear, subsequent `$match` stages cannot use indexes.

### $lookup: Simple vs Pipeline Form

```typescript
// PREFER simple form — uses index on foreignField directly
{ $lookup: { from: 'users', localField: 'userId', foreignField: '_id', as: 'user' } }

// Use pipeline form only when filtering/reshaping joined docs
{
  $lookup: {
    from: 'users',
    let: { uid: '$userId' },
    pipeline: [
      { $match: { $expr: { $eq: ['$_id', '$$uid'] } } },
      { $project: { name: 1, email: 1 } },  // trim joined doc
    ],
    as: 'user',
  },
}
```

### Pagination with Aggregation

```typescript
// Cursor-based pagination (preferred over skip/limit for large datasets)
async findPaginated(lastId?: string, limit = 20) {
  const match: any = { status: 'active' }
  if (lastId) match._id = { $gt: new Types.ObjectId(lastId) }

  return this.orderModel.aggregate([
    { $match: match },
    { $sort: { _id: 1 } },
    { $limit: limit + 1 },  // fetch one extra to detect hasMore
  ])
}
```

## Transactions

### Prerequisites

Multi-document transactions require a **replica set** (MongoDB 4.0+) or **sharded cluster** (4.2+). Single-document writes are already atomic — don't wrap them in transactions.

### Recommended: withTransaction()

Handles commit, abort, and transient error retry automatically.

```typescript
async transferFunds(fromId: string, toId: string, amount: number) {
  const session = await this.connection.startSession()
  try {
    await session.withTransaction(async () => {
      const from = await this.accountModel.findById(fromId).session(session)
      if (from.balance < amount) throw new Error('Insufficient funds')

      await this.accountModel.findByIdAndUpdate(fromId, { $inc: { balance: -amount } }, { session })
      await this.accountModel.findByIdAndUpdate(toId, { $inc: { balance: amount } }, { session })
      await this.transactionModel.create([{ from: fromId, to: toId, amount }], { session })
    })
  } finally {
    await session.endSession()
  }
}
```

### Transaction Rules

- **Keep transactions short** — long transactions hold locks, abort after 60s default
- **Do not parallelize** inside a transaction — operations must be sequential
- **Use `w: 'majority'`** write concern for durability
- **Read preference must be `primary`** inside transactions
- **Don't wrap single-document operations** — they're already atomic

## Mongoose Patterns for NestJS

### Always Use lean() on Read Endpoints

`lean()` returns plain JS objects — ~3x less memory, no change tracking overhead.

```typescript
// GET endpoint — always lean
async findAll(): Promise<User[]> {
  return this.userModel.find().lean().exec()
}

// PUT/POST endpoint — needs full doc for .save(), hooks, validation
async update(id: string, dto: UpdateUserDto): Promise<User> {
  const user = await this.userModel.findById(id)
  Object.assign(user, dto)
  return user.save()
}
```

| Operation | Use lean() | Reason |
|-----------|-----------|--------|
| GET / read endpoints | Yes | 3x less memory, faster |
| PUT / PATCH / POST | No | Needs `.save()`, hooks, change tracking |
| Aggregation | N/A | Returns plain objects already |
| Streaming cursors | Yes | Critical for large result sets |

### Always Use select() / Projection

```typescript
// BAD — returns all fields including hashed password
const user = await this.userModel.findById(id)

// GOOD — explicit projection
const user = await this.userModel.findById(id).select('firstName lastName email avatar').lean()
```

### Avoid populate() Chains — Use Aggregation

```typescript
// BAD — N+1 queries, no field limiting
const orders = await this.orderModel.find()
  .populate('user')
  .populate('items.product')

// BETTER — limit populate fields + lean
const orders = await this.orderModel.find()
  .populate('user', 'name email')
  .populate('items.product', 'name price')
  .lean()

// BEST for complex joins — single aggregation pipeline
const orders = await this.orderModel.aggregate([
  { $match: { status: 'pending' } },
  { $lookup: { from: 'users', localField: 'userId', foreignField: '_id', as: 'user' } },
  { $unwind: '$user' },
  { $project: { 'user.password': 0 } },
])
```

### Bulk Operations Instead of Loops

```typescript
// BAD — N round trips
for (const item of items) {
  await new this.productModel(item).save()
}

// GOOD — single round trip
await this.productModel.insertMany(items, { ordered: false })

// GOOD — mixed operations in one call
await this.productModel.bulkWrite([
  { insertOne: { document: newProduct } },
  { updateOne: { filter: { sku: 'ABC' }, update: { $inc: { qty: -1 } } } },
  { deleteOne: { filter: { sku: 'DEPRECATED' } } },
])
```

### Virtuals with lean()

By default, `lean()` strips virtuals. Use `mongoose-lean-virtuals`:

```typescript
import mongooseLeanVirtuals from 'mongoose-lean-virtuals'

UserSchema.plugin(mongooseLeanVirtuals)

UserSchema.virtual('fullName').get(function () {
  return `${this.firstName} ${this.lastName}`
})

// In service:
await this.userModel.find().lean({ virtuals: true })
```

### Discriminators (Schema Inheritance)

```typescript
// Base event schema
@Schema({ discriminatorKey: 'kind', timestamps: true })
export class Event {
  @Prop({ required: true })
  kind: string

  @Prop()
  occurredAt: Date
}

// Click event extends base
@Schema()
export class ClickEvent {
  @Prop() url: string
  @Prop() elementId: string
}

// Module registration
MongooseModule.forFeature([{
  name: Event.name,
  schema: EventSchema,
  discriminators: [{ name: ClickEvent.name, schema: ClickEventSchema }],
}])
```

### Connection Events — Always Handle

```typescript
// database.module.ts
mongoose.connection.on('error', (err) => logger.error('MongoDB error:', err))
mongoose.connection.on('disconnected', () => logger.warn('MongoDB disconnected'))
mongoose.connection.on('reconnected', () => logger.info('MongoDB reconnected'))

process.on('SIGINT', async () => {
  await mongoose.connection.close()
  process.exit(0)
})
```

## Connection Management

### Production Configuration

```typescript
MongooseModule.forRoot(process.env.MONGODB_URI, {
  maxPoolSize:              10,      // tune to load — default 100 is often too high
  minPoolSize:               2,      // keep connections warm
  serverSelectionTimeoutMS: 5000,    // fail fast if server unreachable
  socketTimeoutMS:          45000,   // close idle sockets
  connectTimeoutMS:         10000,   // TCP connection timeout
  heartbeatFrequencyMS:     10000,   // health check frequency
  maxIdleTimeMS:            30000,   // close long-idle connections
  family:                    4,      // IPv4, skip IPv6 probe
})
```

### Pool Size Rule of Thumb

```
maxPoolSize = (numCPUs * 2) + effectiveSpindleCount
```

Start with 10-20 for typical API servers. With 10 pods at `maxPoolSize: 100`, you get 1,000 connections to MongoDB — check your Atlas tier limits.

## Data Modeling Patterns

### Bucket Pattern (Time Series)

Group related time-series data into buckets instead of one doc per reading.

```typescript
@Schema()
export class SensorBucket {
  @Prop({ required: true, index: true })
  sensorId: string

  @Prop({ required: true })
  startDate: Date

  @Prop({ required: true })
  endDate: Date

  @Prop({ type: [{ timestamp: Date, value: Number }] })
  measurements: Array<{ timestamp: Date; value: number }>

  @Prop({ default: 0 })
  count: number

  @Prop({ default: 0 })
  sum: number  // pre-computed for fast avg = sum/count
}
```

> MongoDB 5.0+ has native time series collections — prefer those for new workloads.

### Subset Pattern

Embed only the most-recent/relevant subset; full data in a separate collection.

```typescript
@Schema({ timestamps: true })
export class Post {
  @Prop() title: string
  @Prop() body: string

  // Only last 10 comments — enough for initial render
  @Prop({ type: [{ author: String, text: String, createdAt: Date }], default: [] })
  recentComments: Array<{ author: string; text: string; createdAt: Date }>

  @Prop({ default: 0 })
  commentCount: number
}
// Full comments in separate `comments` collection — fetched on "Load more"
```

### Computed Pattern

Pre-compute expensive aggregations; update on writes.

```typescript
@Schema({ timestamps: true })
export class ProductStats {
  @Prop({ type: Types.ObjectId, ref: 'Product', unique: true })
  productId: Types.ObjectId

  @Prop({ default: 0 })
  totalRevenue: number

  @Prop({ default: 0 })
  orderCount: number
}

// On sale — atomic update, no aggregation needed on read
await this.productStatsModel.findOneAndUpdate(
  { productId },
  { $inc: { totalRevenue: saleAmount, orderCount: 1 } },
  { upsert: true }
)
```

### Outlier Pattern

Handle documents with abnormally large arrays by flagging overflow.

```typescript
// Main document — bounded array
{ username: 'celebrity', followers: [...first1000], hasOverflow: true }

// Overflow collection
{ userId: ObjectId, followers: [...next1000], page: 2 }
```

## Common Anti-Patterns

### 1. Unbounded Arrays

```typescript
// BAD — array grows without limit, hits 16MB doc limit
@Prop({ type: [Types.ObjectId] })
followers: Types.ObjectId[]  // could be 1M entries

// GOOD — separate collection with parent reference
@Schema({ timestamps: true })
export class Follow {
  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  followedId: Types.ObjectId

  @Prop({ type: Types.ObjectId, ref: 'User', required: true, index: true })
  followerId: Types.ObjectId
}
```

### 2. No lean() on Read Endpoints

Full Mongoose documents use ~3x the memory of plain objects. On an API serving thousands of requests, this adds up fast.

### 3. Missing timestamps

```typescript
// BAD — no audit trail
@Schema()

// GOOD — always
@Schema({ timestamps: true })
```

### 4. save() in a Loop

```typescript
// BAD — 100 round trips
for (const item of items) await new this.model(item).save()

// GOOD — 1 round trip
await this.model.insertMany(items, { ordered: false })
```

### 5. Querying Without Indexes

Run `explain('executionStats')` on slow queries. If `totalDocsExamined` >> `totalKeysExamined`, you're missing an index.

### 6. $lookup Before $match

Always filter first, join last. A `$lookup` on 100K docs followed by `$match` is orders of magnitude slower than filtering to 100 docs first.

### 7. populate() N+1

Deep `.populate()` chains fire multiple queries. For complex joins, use aggregation `$lookup`.

### 8. Not Using Projection

Every field transmitted costs network and memory. Use `.select()` to fetch only what you need.

### 9. Wrapping Single-Doc Ops in Transactions

Single-document writes are already atomic in MongoDB. Transactions add overhead and require replica sets — don't use them unnecessarily.

### 10. Ignoring Connection Pool Sizing

Default `maxPoolSize: 100` * 10 pods = 1,000 connections. Atlas tiers have limits. Start with 10-20 per process and tune based on monitoring.

## Quick Reference

| Task | Pattern |
|------|---------|
| Read endpoint | `.find().lean().exec()` |
| Read with few fields | `.select('a b c').lean()` |
| Simple join | `.populate('ref', 'field1 field2').lean()` |
| Complex join | Aggregation `$lookup` |
| Compound index order | Equality → Sort → Range |
| Bulk insert | `Model.insertMany(docs, { ordered: false })` |
| Mixed bulk ops | `Model.bulkWrite([...])` |
| Transaction | `session.withTransaction(async () => { ... })` |
| Auto-delete expired docs | TTL index (`expires: '24h'`) |
| Count without fetching | `Model.countDocuments(filter)` |
| Check if exists | `Model.exists(filter)` |
| Atomic increment | `Model.findByIdAndUpdate(id, { $inc: { count: 1 } })` |
| Upsert | `findOneAndUpdate(filter, update, { upsert: true, new: true })` |

## Further Reading

For detailed reference on specific topics, see:
- `references/mongoose-patterns.md` — Advanced patterns: pre/post hooks, custom methods, statics, plugins, change streams, cursor-based streaming

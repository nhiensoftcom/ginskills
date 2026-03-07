# Clean Code Principles — Review Reference

Practical guide for reviewing code against clean code, SOLID, and design principles. All examples use TypeScript in a NestJS/Next.js context.

## Table of Contents
1. [SOLID Principles](#solid-principles)
2. [DRY, KISS, YAGNI](#dry-kiss-yagni)
3. [Code Smells Catalog](#code-smells-catalog)
4. [Anti-Patterns](#anti-patterns)
5. [Refactoring Recipes](#refactoring-recipes)

---

## SOLID Principles

### S — Single Responsibility Principle (SRP)

**Rule:** A class should have only one reason to change.

Bad — service does too much:
```typescript
@Injectable()
export class OrderService {
  async createOrder(dto: CreateOrderDto, user: User) { /* ... */ }
  async sendOrderEmail(order: Order) { /* ... */ }        // ← email is not order logic
  async generateInvoicePdf(order: Order) { /* ... */ }    // ← PDF generation is not order logic
  async syncToAnalytics(order: Order) { /* ... */ }       // ← analytics is not order logic
}
```

Good — each class has one job:
```typescript
@Injectable()
export class OrderService {
  constructor(
    private readonly emailService: EmailService,
    private readonly invoiceService: InvoiceService,
    private readonly eventEmitter: EventEmitter2,
  ) {}

  async createOrder(dto: CreateOrderDto, user: User) {
    const order = await this.orderModel.create({ ...dto, userId: user._id });
    this.eventEmitter.emit('order.created', order);  // Other services react to events
    return order;
  }
}
```

**Review checklist:**
- Service has >10 public methods → likely violates SRP, split by domain concern
- Service injects >5 dependencies → may be doing too much
- Controller has business logic beyond validation + delegation → move to service
- A change in one feature requires editing this class → it has multiple responsibilities

### O — Open/Closed Principle (OCP)

**Rule:** Open for extension, closed for modification.

Bad — modifying existing code for each new case:
```typescript
@Injectable()
export class NotificationService {
  async send(type: string, data: any) {
    if (type === 'email') { /* send email */ }
    else if (type === 'sms') { /* send SMS */ }
    else if (type === 'push') { /* send push */ }
    // Adding Slack? Must modify this class.
  }
}
```

Good — extend through new implementations:
```typescript
interface NotificationChannel {
  send(data: NotificationPayload): Promise<void>;
}

@Injectable()
export class EmailChannel implements NotificationChannel { /* ... */ }
@Injectable()
export class SmsChannel implements NotificationChannel { /* ... */ }
@Injectable()
export class SlackChannel implements NotificationChannel { /* ... */ }

@Injectable()
export class NotificationService {
  constructor(
    @Inject('NOTIFICATION_CHANNELS') private channels: NotificationChannel[],
  ) {}

  async send(channelType: string, data: NotificationPayload) {
    const channel = this.channels.find(c => c.type === channelType);
    await channel.send(data);
  }
}
```

**Review checklist:**
- Growing if/else or switch chains for variants → use strategy/registry pattern
- Adding a new feature type requires editing existing service → violates OCP
- Configuration-driven behavior is hardcoded → extract to config or plugins

### L — Liskov Substitution Principle (LSP)

**Rule:** Subtypes must be substitutable for their base types without breaking behavior.

Bad — subclass changes expected behavior:
```typescript
class ReadOnlyRepository<T> {
  async findById(id: string): Promise<T> { /* ... */ }
  async save(entity: T): Promise<T> { throw new Error('Read only!'); }  // ← breaks contract
}
```

Good — separate interfaces for different capabilities:
```typescript
interface Readable<T> {
  findById(id: string): Promise<T>;
}
interface Writable<T> {
  save(entity: T): Promise<T>;
}
interface Repository<T> extends Readable<T>, Writable<T> {}
```

**Review checklist:**
- Overridden methods that throw "not supported" → violates LSP
- Subclasses that ignore or nullify parent behavior → redesign the hierarchy
- Type assertions needed after using a base type → polymorphism is broken

### I — Interface Segregation Principle (ISP)

**Rule:** Don't force implementations to depend on methods they don't use.

Bad — fat interface:
```typescript
interface UserService {
  findById(id: string): Promise<User>;
  createUser(dto: CreateUserDto): Promise<User>;
  deleteUser(id: string): Promise<void>;
  sendWelcomeEmail(user: User): Promise<void>;    // ← not every consumer needs this
  generateReport(userId: string): Promise<Buffer>; // ← not every consumer needs this
}
```

Good — focused interfaces:
```typescript
interface UserReader {
  findById(id: string): Promise<User>;
}
interface UserWriter {
  createUser(dto: CreateUserDto): Promise<User>;
  deleteUser(id: string): Promise<void>;
}
```

**Review checklist:**
- Interface has methods that some implementations leave empty → split it
- Classes implement interfaces where half the methods are no-ops → ISP violation
- Consumers import a service but only use 1-2 of its 10+ methods → interface is too broad

### D — Dependency Inversion Principle (DIP)

**Rule:** Depend on abstractions, not concretions.

Bad — direct dependency on implementation:
```typescript
@Injectable()
export class OrderService {
  private stripe = new Stripe(process.env.STRIPE_KEY);  // ← concrete dependency

  async charge(amount: number) {
    return this.stripe.charges.create({ amount });
  }
}
```

Good — depend on abstraction via NestJS DI:
```typescript
interface PaymentProvider {
  charge(amount: number, currency: string): Promise<PaymentResult>;
}

@Injectable()
export class StripeProvider implements PaymentProvider { /* ... */ }

@Injectable()
export class OrderService {
  constructor(
    @Inject('PAYMENT_PROVIDER') private paymentProvider: PaymentProvider,
  ) {}

  async charge(amount: number) {
    return this.paymentProvider.charge(amount, 'usd');
  }
}
```

**Review checklist:**
- `new ExternalService()` inside business logic → inject it instead
- Direct SDK imports in services (aws-sdk, stripe, etc.) → wrap in abstraction
- High-level modules importing from low-level modules → invert the dependency

---

## DRY, KISS, YAGNI

### DRY — Don't Repeat Yourself

**Rule:** Every piece of knowledge has a single, unambiguous representation.

Common DRY violations in our stack:

| Violation | Fix |
|---|---|
| Same validation logic in DTO and frontend Zod schema | Share validation via a common schema package or derive one from the other |
| Identical error handling in every controller method | Use NestJS exception filters |
| Copy-pasted Mongoose query patterns across services | Extract to a base repository or shared query builder |
| Same API response shape defined in multiple DTOs | Create a base DTO and extend |
| Repeated auth check logic | Use guards and decorators |

**But beware of wrong DRY:** Don't merge things that happen to look similar but serve different purposes. Two functions with identical code TODAY might evolve differently. Ask: "If one changes, must the other change too?" If no, they aren't true duplicates.

### KISS — Keep It Simple, Stupid

**Rule:** The simplest solution that works correctly is the best solution.

Red flags for over-engineering:
- Abstract factory pattern for 2 variants → just use a simple if/else
- Generic base class with 5 type parameters used by 1 subclass → remove the generics
- Custom event bus when NestJS EventEmitter2 works fine
- Hand-rolled caching layer when `@nestjs/cache-manager` exists
- Complex class hierarchy when composition would be simpler

**Review question:** "Could a mid-level developer understand this code in 5 minutes?" If not, it might be too complex.

### YAGNI — You Ain't Gonna Need It

**Rule:** Don't build it until you actually need it.

Red flags:
- Unused exported functions, types, or interfaces
- Configuration options that are never set to anything other than the default
- Abstract base classes with only one concrete implementation
- Plugin/extension architecture with zero plugins
- Feature flags for features that shipped months ago
- "Flexible" data structures that only store one type of data

---

## Code Smells Catalog

Quick-reference for the most common code smells in our stack:

### Bloaters (too big)
| Smell | Threshold | Action |
|---|---|---|
| Long method | >30 lines | Extract methods by responsibility |
| Large class | >200 lines or >10 public methods | Split into focused classes |
| Long parameter list | >3 params | Use options object / DTO |
| Primitive obsession | Strings/numbers for domain concepts | Create value objects or enums |
| Data clumps | Same group of params passed together | Extract to a class/interface |

### Object-Orientation Abusers
| Smell | Sign | Action |
|---|---|---|
| Switch/if chains on type | `if (type === 'A') ... else if (type === 'B')` | Use polymorphism or strategy pattern |
| Refused bequest | Subclass doesn't use inherited methods | Rethink hierarchy, prefer composition |
| Temporary field | Fields only set in some scenarios | Extract to separate class or use Optional |

### Change Preventers
| Smell | Sign | Action |
|---|---|---|
| Divergent change | One class changed for many different reasons | Split by SRP |
| Shotgun surgery | One change touches many files | Consolidate related logic |
| Parallel inheritance | Adding a subclass requires adding sibling subclass | Merge hierarchies or use composition |

### Dispensables (remove them)
| Smell | Sign | Action |
|---|---|---|
| Dead code | Unreachable or uncalled code | Delete it (git has history) |
| Speculative generality | Unused abstractions "for the future" | Delete until needed (YAGNI) |
| Duplicate code | Same logic in multiple places | Extract to shared utility |
| Lazy class | Class that does too little | Inline it into its caller |
| Comments explaining bad code | `// This increments i by 1` | Rewrite the code to be clear |

### Couplers (too connected)
| Smell | Sign | Action |
|---|---|---|
| Feature envy | Method uses another class's data more than its own | Move method to that class |
| Inappropriate intimacy | Classes access each other's private details | Establish proper public interfaces |
| Message chains | `a.getB().getC().getD()` | Provide a direct method |
| Middle man | Class delegates everything without adding value | Remove and call directly |

---

## Anti-Patterns

### Backend Anti-Patterns (NestJS)

**Fat Controller:**
```typescript
// BAD: Controller with business logic
@Post()
async create(@Body() dto: CreateItemDto) {
  const exists = await this.itemModel.findOne({ name: dto.name });  // ← DB access in controller
  if (exists) throw new ConflictException();
  const item = await this.itemModel.create(dto);
  await this.emailService.send(item.userId, 'Item created');        // ← side effects in controller
  return item;
}
```

**Service Locator (anti-DI):**
```typescript
// BAD: Fetching services manually instead of injecting
@Injectable()
export class OrderService {
  async process(orderId: string) {
    const emailService = this.moduleRef.get(EmailService);  // ← defeats DI, untestable
    await emailService.send(...);
  }
}
```

**Catch and Ignore:**
```typescript
// BAD: Swallowing errors
try {
  await this.paymentService.charge(order);
} catch (e) {
  console.log(e);  // ← error logged but not handled, order proceeds as if payment succeeded
}
```

**Stringly Typed:**
```typescript
// BAD: Using strings where enums/types belong
async updateStatus(id: string, status: string) { /* ... */ }
// GOOD:
async updateStatus(id: string, status: OrderStatus) { /* ... */ }
```

### Frontend Anti-Patterns (Next.js / React)

**Prop Drilling:**
```typescript
// BAD: Passing props through 4+ levels of components
<App user={user}>
  <Layout user={user}>
    <Sidebar user={user}>
      <UserAvatar user={user} />  // ← just use context or Zustand
```

**useEffect for Everything:**
```typescript
// BAD: Derived state in useEffect
const [fullName, setFullName] = useState('');
useEffect(() => {
  setFullName(`${firstName} ${lastName}`);  // ← just compute it
}, [firstName, lastName]);

// GOOD: Compute directly
const fullName = `${firstName} ${lastName}`;
```

**God Component:**
```typescript
// BAD: 500-line component with mixed concerns
export function Dashboard() {
  // 20 state variables
  // 10 useEffects
  // 15 handler functions
  // 300 lines of JSX
}
// GOOD: Split into focused components with custom hooks
```

---

## Refactoring Recipes

Common refactoring patterns to suggest during reviews:

| Current Code | Refactoring | Result |
|---|---|---|
| Long method with comment sections | **Extract Method** | Small, named methods that self-document |
| Repeated if/else on type | **Replace Conditional with Polymorphism** | Strategy pattern or class hierarchy |
| Multiple params always passed together | **Introduce Parameter Object** | DTO or interface |
| Nested callbacks or promise chains | **Replace with async/await** | Flat, readable async code |
| Boolean method params | **Replace Parameter with Explicit Methods** | `publish()` and `saveDraft()` instead of `save(isPublished)` |
| Raw string/number domain values | **Replace Primitive with Value Object** | `OrderId`, `Money`, `Email` types |
| God service | **Extract Class** | Multiple focused services |
| Copy-paste with small variations | **Extract with Parameters** | Shared function with config |
| Manual resource cleanup | **Use try/finally or disposable** | Guaranteed cleanup |

# Active Life Backend - Coding Patterns & Conventions

## Project Structure Convention

Every feature module follows this structure:
```
src/<module-name>/
├── <module-name>.module.ts
├── <module-name>.controller.ts
├── <module-name>.service.ts
└── dto/
    ├── create-<module-name>.dto.ts
    └── update-<module-name>.dto.ts
```

## Module Pattern

```typescript
import { Module } from '@nestjs/common';
import { XxxController } from './xxx.controller';
import { XxxService } from './xxx.service';

@Module({
  controllers: [XxxController],
  providers: [XxxService],
  exports: [XxxService],  // Only if other modules need this service
})
export class XxxModule {}
```

## Controller Pattern

```typescript
import { Controller, Get, Post, Body, Param, Query, Patch, Delete } from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation } from '@nestjs/swagger';
import { Public } from 'src/decorators/customize';
import { ResponseMessage, User } from 'src/decorators/customize';
import { IUser } from 'src/interface/users.interface';

@Controller('xxx')
@ApiTags('xxx')
export class XxxController {
  constructor(private readonly xxxService: XxxService) {}

  @Post()
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Create xxx' })
  @ResponseMessage('Created successfully')
  create(@Body() dto: CreateXxxDto, @User() user: IUser) {
    return this.xxxService.create(dto, user);
  }

  @Get()
  @Public()
  @ApiOperation({ summary: 'Get all xxx' })
  findAll(@Query() query: any) {
    return this.xxxService.findAll(query);
  }

  @Get(':id')
  @Public()
  findOne(@Param('id') id: string) {
    return this.xxxService.findOne(id);
  }

  @Patch(':id')
  @ApiBearerAuth()
  update(@Param('id') id: string, @Body() dto: UpdateXxxDto) {
    return this.xxxService.update(id, dto);
  }

  @Delete(':id')
  @ApiBearerAuth()
  remove(@Param('id') id: string) {
    return this.xxxService.remove(id);
  }
}
```

## Service Pattern

```typescript
import { Injectable, BadRequestException, NotFoundException } from '@nestjs/common';
import { PrismaService } from 'src/prisma/prisma.service';

@Injectable()
export class XxxService {
  constructor(private prismaService: PrismaService) {}

  async create(dto: CreateXxxDto, user?: IUser) {
    // Check for duplicates if needed
    const existing = await this.prismaService.xxx.findUnique({
      where: { name: dto.name },
    });
    if (existing) {
      throw new BadRequestException('Already exists');
    }

    return this.prismaService.xxx.create({
      data: {
        ...dto,
        slug: this.generateSlug(dto.name),  // If applicable
      },
    });
  }

  async findAll(query: any) {
    const { page = 1, limit = 10, search } = query;
    const skip = (page - 1) * limit;

    const where = search
      ? { name: { contains: search, mode: 'insensitive' as const } }
      : {};

    const [data, total] = await Promise.all([
      this.prismaService.xxx.findMany({
        where,
        skip,
        take: +limit,
        orderBy: { createdAt: 'desc' },
      }),
      this.prismaService.xxx.count({ where }),
    ]);

    return {
      data,
      meta: {
        total,
        page: +page,
        limit: +limit,
        totalPages: Math.ceil(total / +limit),
      },
    };
  }

  async findOne(id: string) {
    const item = await this.prismaService.xxx.findUnique({
      where: { id },
      include: { /* relations */ },
    });
    if (!item) {
      throw new NotFoundException('Not found');
    }
    return item;
  }

  async update(id: string, dto: UpdateXxxDto) {
    await this.findOne(id);  // Ensure exists
    return this.prismaService.xxx.update({
      where: { id },
      data: dto,
    });
  }

  async remove(id: string) {
    await this.findOne(id);  // Ensure exists
    return this.prismaService.xxx.delete({ where: { id } });
  }
}
```

## DTO Pattern

```typescript
import { ApiProperty } from '@nestjs/swagger';
import { IsString, IsNotEmpty, IsOptional, IsNumber, IsEnum, IsArray } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateXxxDto {
  @ApiProperty({ example: 'Example name' })
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiProperty({ example: 100 })
  @IsNumber()
  @Type(() => Number)  // For query params auto-conversion
  price: number;

  @ApiProperty({ enum: ProductStatus })
  @IsEnum(ProductStatus)
  status: ProductStatus;

  @ApiProperty({ type: [String] })
  @IsArray()
  @IsString({ each: true })
  images: string[];
}
```

**Update DTO** — typically partial:
```typescript
import { PartialType } from '@nestjs/mapped-types';
import { CreateXxxDto } from './create-xxx.dto';

export class UpdateXxxDto extends PartialType(CreateXxxDto) {}
```

## Response Format

All responses are wrapped by `TransformInterceptor`:
```typescript
// Success response
{
  "statusCode": 200,
  "message": "Success",  // From @ResponseMessage() or default
  "data": { ... }        // Actual data
}

// Error response (from exceptions)
{
  "statusCode": 400,
  "message": "Bad Request",
  "error": "Detailed error message"
}
```

## Slug Generation

Vietnamese-aware slug generation (remove diacritics):
```typescript
private generateSlug(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')  // Remove diacritics
    .replace(/đ/g, 'd').replace(/Đ/g, 'D')
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .trim();
}
```

## Pagination Pattern

Services return paginated data with meta:
```typescript
{
  data: [...items],
  meta: {
    total: 100,
    page: 1,
    limit: 10,
    totalPages: 10
  }
}
```

## Error Handling

Use NestJS built-in exceptions:
```typescript
throw new BadRequestException('Validation error message');
throw new NotFoundException('Resource not found');
throw new ForbiddenException('Access denied');
throw new UnauthorizedException('Invalid credentials');
```

## Naming Conventions

- **Files**: kebab-case (`create-product.dto.ts`)
- **Classes**: PascalCase (`CreateProductDto`)
- **Methods**: camelCase (`findAll`, `createOrder`)
- **Database tables**: PascalCase in Prisma schema (auto-mapped to snake_case)
- **API routes**: kebab-case (`/api/v1/inventory-product`)
- **Env vars**: SCREAMING_SNAKE_CASE (`JWT_CLIENT_ACCESS_TOKEN_SECRET`)

## Import Conventions

```typescript
// NestJS core
import { Injectable, Controller, Module } from '@nestjs/common';
// Swagger
import { ApiTags, ApiBearerAuth, ApiProperty } from '@nestjs/swagger';
// Validation
import { IsString, IsNotEmpty } from 'class-validator';
// Project internals (absolute paths from src/)
import { PrismaService } from 'src/prisma/prisma.service';
import { Public, User, ResponseMessage } from 'src/decorators/customize';
import { IUser } from 'src/interface/users.interface';
```

## Logging

The `LoggingInterceptor` automatically logs:
- HTTP method, URL, IP
- User info (if authenticated)
- Response status code
- Execution time (ms)
- Error details on failure

No need to add manual logging in services unless debugging specific flows.

## Global Configuration (main.ts)

```typescript
// Applied globally:
app.useGlobalGuards(new JwtAuthGuard(...));           // Auth on all routes
app.useGlobalPipes(new ValidationPipe({
  whitelist: true,           // Strip unknown properties
  transform: true,           // Auto-transform types
  transformOptions: { enableImplicitConversion: true },
}));
app.useGlobalInterceptors(
  new LoggingInterceptor(),
  new TransformInterceptor(reflector),
);

// CORS: all origins allowed
// Rate limit: 10 requests / 60 seconds
// API versioning: URI-based (/api/v1/, /api/v2/)
// Swagger at /api
```

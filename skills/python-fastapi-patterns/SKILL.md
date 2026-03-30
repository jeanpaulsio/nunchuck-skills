---
name: python-fastapi-patterns
description: Deep reference for Python/FastAPI patterns -- async SQLAlchemy, Pydantic v2, service layer, dependency injection, error handling, testing, background jobs. Covers non-obvious gotchas and production patterns.
---

# Python / FastAPI / SQLAlchemy Patterns

Production patterns for FastAPI applications with async SQLAlchemy 2.0 and Pydantic v2. Focused on things that are non-obvious or that people commonly get wrong.

---

## Table of Contents

1. [Dependency Injection](#dependency-injection)
2. [Async SQLAlchemy Session Management](#async-sqlalchemy-session-management)
3. [SQLAlchemy ORM Patterns](#sqlalchemy-orm-patterns)
4. [Pydantic v2 Patterns](#pydantic-v2-patterns)
5. [Service Layer Architecture](#service-layer-architecture)
6. [Error Handling](#error-handling)
7. [Authentication & Authorization](#authentication--authorization)
8. [Pagination](#pagination)
9. [Background Jobs](#background-jobs)
10. [Testing](#testing)
11. [Database Migrations](#database-migrations)
12. [Configuration](#configuration)
13. [Concurrency & Locking](#concurrency--locking)
14. [Quick Reference](#quick-reference)

---

## Dependency Injection

### Extract Ownership Checks into Dependencies

Every route that accesses a user-owned resource repeats the same lookup + ownership check. Extract it.

```python
# BAD: Duplicated in every route
@router.get("/decks/{deck_id}")
async def get_deck(
    deck_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    deck = await repo.get_by_id(deck_id)
    if not deck or deck.user_id != user.id:
        raise NotFoundError("Deck")
    return deck

@router.put("/decks/{deck_id}")
async def update_deck(
    deck_id: UUID,
    body: DeckUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    deck = await repo.get_by_id(deck_id)
    if not deck or deck.user_id != user.id:
        raise NotFoundError("Deck")  # same check, again
    ...

# GOOD: Reusable dependency
async def get_owned_deck(
    deck_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> Deck:
    repo = DeckRepository(db)
    deck = await repo.get_by_id(deck_id)
    if not deck or deck.user_id != user.id:
        raise NotFoundError("Deck")
    return deck

@router.get("/decks/{deck_id}")
async def get_deck(deck: Deck = Depends(get_owned_deck)):
    return deck

@router.put("/decks/{deck_id}")
async def update_deck(body: DeckUpdate, deck: Deck = Depends(get_owned_deck)):
    ...
```

FastAPI caches dependency results within a single request. If `get_current_user` is used by multiple chained dependencies, it only runs once.

### Use Annotated Types for Cleaner Signatures

```python
from typing import Annotated

DbSession = Annotated[AsyncSession, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]

# Before
@router.get("/decks")
async def list_decks(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    pagination: PaginationParams = Depends(),
): ...

# After
@router.get("/decks")
async def list_decks(
    user: CurrentUser,
    db: DbSession,
    pagination: PaginationParams = Depends(),
): ...
```

### Router-Level Dependencies Over Middleware

```python
# BAD: Auth middleware with fragile whitelist
@app.middleware("http")
async def auth_middleware(request: Request, call_next):
    public_routes = ["/", "/login", "/health"]
    if request.url.path not in public_routes:
        # Verify token... easy to forget adding new public routes
        ...
    return await call_next(request)

# GOOD: Router-level protection is structural
protected = APIRouter(dependencies=[Depends(get_current_user)])
public = APIRouter()

app.include_router(protected, prefix="/api")
app.include_router(public)

# Every route on `protected` is automatically auth-gated
# New public routes go on `public` -- impossible to forget
```

### When NOT to Use Depends

```python
# WRONG: Wrapping pure computation in Depends
async def calculate_tax(amount: float) -> float:
    return amount * 0.1

@router.post("/order")
async def create_order(tax: float = Depends(calculate_tax)): ...

# RIGHT: Depends is for request-scoped resources (DB, auth, config)
@router.post("/order")
async def create_order(amount: float, db: DbSession):
    tax = amount * 0.1  # just call it
```

Use `Depends` for: database sessions, auth, rate limiters, request-scoped config.
Don't use `Depends` for: pure functions, one-off logic, values you'd cache with `@lru_cache`.

---

## Async SQLAlchemy Session Management

### expire_on_commit=False Is Mandatory for Async

This is the single most common source of production crashes with async SQLAlchemy.

```python
# BAD: Default expire_on_commit=True
async_session_factory = async_sessionmaker(engine, class_=AsyncSession)
# After commit(), all attributes expire. Accessing them triggers
# a SYNCHRONOUS lazy reload, which raises MissingGreenlet in async context.

# GOOD: Disable expiry after commit
async_session_factory = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,  # CRITICAL
)
```

### Eager Loading Is Not Optional

In sync SQLAlchemy, lazy loading "just works" -- it fires a query when you access a relationship. In async, lazy loading is a synchronous I/O call that crashes.

```python
# BAD: Lazy loading in async context
async def get_deck_with_problems(db: AsyncSession, deck_id: UUID) -> Deck:
    result = await db.execute(select(Deck).where(Deck.id == deck_id))
    deck = result.scalar_one()
    problems = deck.problems  # CRASH: MissingGreenlet
    return deck

# GOOD: Explicit eager loading
from sqlalchemy.orm import selectinload, joinedload

async def get_deck_with_problems(db: AsyncSession, deck_id: UUID) -> Deck:
    result = await db.execute(
        select(Deck)
        .where(Deck.id == deck_id)
        .options(selectinload(Deck.problems))
    )
    return result.scalar_one()
```

**Which eager loading strategy to use:**

| Strategy | Best for | How it works |
|----------|----------|-------------|
| `selectinload` | One-to-many collections | Separate `SELECT ... WHERE id IN (...)` query. Default choice. |
| `joinedload` | Many-to-one, one-to-one | Uses JOIN. Avoid for collections (creates cartesian product). |
| `subqueryload` | Large one-to-many | Subquery instead of IN clause. Use when selectinload generates too many params. |

### Use lazy="raise" to Catch Mistakes Early

```python
class Deck(Base):
    __tablename__ = "decks"
    problems: Mapped[list["Problem"]] = relationship(lazy="raise")
    # Now any accidental lazy load raises immediately in dev
    # instead of silently crashing in production
```

### Never Share a Session Across Concurrent Tasks

```python
# BAD: Same session in asyncio.gather -- race condition
session = async_session_factory()
await asyncio.gather(
    service_a.do_work(session),
    service_b.do_work(session),  # NOT thread/task safe
)

# GOOD: One session per concurrent task
async def fetch_one(uid: UUID) -> User:
    async with async_session_factory() as db:
        return await db.get(User, uid)

results = await asyncio.gather(*[fetch_one(uid) for uid in ids])
```

### Session-per-Request Transaction Boundary

```python
# The correct pattern: dependency manages transaction lifecycle
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with async_session_factory() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise

# Services use flush() -- NOT commit()
# flush() sends SQL to the database within the transaction
# commit() happens once at the request boundary via get_db
class BaseRepository:
    async def create(self, data, **extra) -> ModelT:
        obj = self.model(**data.model_dump(), **extra)
        self.db.add(obj)
        await self.db.flush()      # sends INSERT, gets generated ID
        await self.db.refresh(obj) # loads server defaults (created_at, etc.)
        return obj
```

**Why flush, not commit, in services:** If a request calls two services and the second one fails, the entire transaction rolls back -- including the first service's work. If the first service had called `commit()`, its work is already permanent and you have an inconsistent state.

### Detached Instance Gotcha After Session Close

```python
# Without expire_on_commit=False, this crashes:
async def get_user(db: AsyncSession, user_id: UUID) -> User:
    user = await db.get(User, user_id)
    await db.commit()
    return user  # user.email triggers lazy reload -- CRASH

# With expire_on_commit=False, attributes stay loaded after commit
# This is why the setting is critical
```

---

## SQLAlchemy ORM Patterns

### Modern Mapped Syntax (2.0+)

```python
from sqlalchemy.orm import Mapped, mapped_column, DeclarativeBase
from sqlalchemy import String, DateTime, func
from datetime import datetime
import uuid

class Base(DeclarativeBase):
    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
```

### Postgres Enum Helper

Python enums and Postgres enums have a case mismatch. Python uses `UPPERCASE` by default, Postgres expects `lowercase`.

```python
import enum
from sqlalchemy import Enum

class Difficulty(enum.StrEnum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"

def pg_enum(enum_class: type[enum.StrEnum], name: str) -> Enum:
    """Create SQLAlchemy Enum with lowercase values for Postgres."""
    return Enum(
        enum_class,
        name=name,
        values_callable=lambda e: [x.value for x in e],
    )

# Usage in model
class Problem(TimestampMixin, Base):
    __tablename__ = "problems"
    difficulty: Mapped[Difficulty] = mapped_column(
        pg_enum(Difficulty, "difficulty"), default=Difficulty.MEDIUM
    )
```

### Explicit Column Selection for Lists

TEXT columns live in PostgreSQL's TOAST tables and are expensive to retrieve in bulk.

```python
# BAD: select(Problem) loads ALL columns including 5 TEXT fields
result = await db.execute(select(Problem).where(Problem.user_id == user_id))

# GOOD: select only what the list view needs
_LIST_COLUMNS = [
    Problem.id, Problem.title, Problem.slug,
    Problem.difficulty, Problem.language, Problem.tags,
    Problem.created_at,
]
result = await db.execute(select(*_LIST_COLUMNS).where(Problem.user_id == user_id))
```

### Bulk Updates with CASE WHEN

Single SQL statement for multi-row updates. More efficient than a loop.

```python
from sqlalchemy import case, update

async def reorder_items(
    db: AsyncSession, parent_id: UUID, ordered_ids: list[UUID]
) -> None:
    whens = {item_id: idx for idx, item_id in enumerate(ordered_ids)}
    stmt = (
        update(DeckProblem)
        .where(DeckProblem.deck_id == parent_id)
        .values(position=case(whens, value=DeckProblem.problem_id))
    )
    await db.execute(stmt)
    await db.flush()
```

### Row-Level Locking for Concurrent Safety

```python
async def add_item_to_deck(
    db: AsyncSession, deck_id: UUID, problem_id: UUID
) -> DeckProblem:
    # Lock the parent row to prevent concurrent position races
    await db.execute(
        select(Deck).where(Deck.id == deck_id).with_for_update()
    )

    # Now safe to read max position and increment
    max_pos = await db.execute(
        select(func.coalesce(func.max(DeckProblem.position), -1) + 1)
        .where(DeckProblem.deck_id == deck_id)
    )
    next_position = max_pos.scalar_one()

    item = DeckProblem(
        deck_id=deck_id,
        problem_id=problem_id,
        position=next_position,
    )
    db.add(item)
    await db.flush()
    await db.refresh(item)
    return item
```

### JSONB for Semi-Structured Data

```python
from sqlalchemy.dialects.postgresql import JSONB

class User(TimestampMixin, Base):
    __tablename__ = "users"
    ai_model_preferences: Mapped[dict[str, str] | None] = mapped_column(
        JSONB, nullable=True, default=None
    )

# Query JSONB fields
stmt = select(User).where(
    User.ai_model_preferences["default_model"].as_string() == "claude-sonnet"
)
```

---

## Pydantic v2 Patterns

### Separate Create/Update/Read Schemas

```python
# Create: required fields with defaults
class DeckCreate(BaseModel):
    title: str = Field(min_length=1, max_length=255)
    description: str = ""

# Update: all fields optional (partial update)
class DeckUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = None

# Read: full response shape
class DeckRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    title: str
    description: str
    created_at: datetime
    updated_at: datetime

# List item: lightweight (no expensive fields)
class DeckListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    problem_count: int
    created_at: datetime
```

### Partial Updates with exclude_unset

```python
async def update(self, id: UUID, data: UpdateSchemaT) -> ModelT:
    obj = await self.get_by_id_or_raise(id)
    # Only update fields the client actually sent
    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(obj, field, value)
    await self.db.flush()
    await self.db.refresh(obj)
    return obj
```

**Why `exclude_unset`:** Without it, `DeckUpdate(title="New")` would also set `description=None`, wiping the existing description. With `exclude_unset=True`, only `title` is included in the update dict.

### field_validator Ordering Trap

Validators only see fields defined BEFORE them in the class.

```python
class UserCreate(BaseModel):
    password: str
    password_confirm: str  # defined AFTER password

    @field_validator("password_confirm")
    @classmethod
    def passwords_match(cls, v: str, info: ValidationInfo) -> str:
        if "password" in info.data and v != info.data["password"]:
            raise ValueError("Passwords don't match")
        return v
        # Works because "password" is defined before "password_confirm"
        # If you swap the field order, info.data["password"] won't exist
```

### model_validator for Cross-Field Validation

```python
class DateRange(BaseModel):
    start_date: date
    end_date: date

    @model_validator(mode="after")
    def end_after_start(self) -> "DateRange":
        if self.end_date < self.start_date:
            raise ValueError("end_date must be after start_date")
        return self
```

### model_validator(mode="before") for Input Normalization

```python
class ProblemCreate(BaseModel):
    tags: list[str] = []

    @model_validator(mode="before")
    @classmethod
    def normalize_tags(cls, data: Any) -> Any:
        # Accept comma-separated string or list
        if isinstance(data, dict) and isinstance(data.get("tags"), str):
            data["tags"] = [t.strip() for t in data["tags"].split(",") if t.strip()]
        return data
```

### Reusable Validators with Annotated

```python
from typing import Annotated
from pydantic import AfterValidator

def validate_slug(v: str) -> str:
    if not v.replace("-", "").isalnum():
        raise ValueError("Slug must be alphanumeric with hyphens")
    return v.lower()

Slug = Annotated[str, AfterValidator(validate_slug)]

# Reuse across models -- zero duplication
class DeckCreate(BaseModel):
    slug: Slug

class ProblemCreate(BaseModel):
    slug: Slug
```

### computed_field for Derived Data

```python
from pydantic import computed_field

class DeckResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    slot_count: int
    filled_slot_count: int

    @computed_field
    @property
    def completion_percentage(self) -> float:
        if self.slot_count == 0:
            return 0.0
        return round(self.filled_slot_count / self.slot_count * 100, 1)
```

### Default Values Are Not Validated

```python
class Config(BaseModel):
    retries: int = -1  # This passes -- default is NOT validated!

    @field_validator("retries")
    @classmethod
    def check_positive(cls, v: int) -> int:
        if v < 0:
            raise ValueError("Must be positive")
        return v

# Config()  -- NO error! Default -1 slips through.
# Fix: add validate_default=True
class Config(BaseModel):
    model_config = ConfigDict(validate_default=True)
    retries: int = -1  # Now this IS validated and raises
```

### Subclass Serialization Trap

```python
class Animal(BaseModel):
    name: str

class Dog(Animal):
    breed: str

class Zoo(BaseModel):
    animal: Animal

zoo = Zoo(animal=Dog(name="Rex", breed="Lab"))
zoo.model_dump()
# {"animal": {"name": "Rex"}}  -- breed is GONE!
# Pydantic serializes to the declared type (Animal), not the runtime type (Dog)

# Fix: use SerializeAsAny
from pydantic import SerializeAsAny

class Zoo(BaseModel):
    animal: SerializeAsAny[Animal]
# Now: {"animal": {"name": "Rex", "breed": "Lab"}}
```

---

## Service Layer Architecture

### Decision Hierarchy

```
Route (thin controller)
  → validates input (Pydantic)
  → delegates to service
  → returns response

Service (business logic)
  → domain rules
  → orchestrates repositories
  → raises domain exceptions

Repository (data access)
  → SQL queries
  → flush/refresh
  → no business logic
```

### Services Must Not Know About HTTP

```python
# BAD: Service raises HTTPException
from fastapi import HTTPException

class DeckService:
    async def get_deck(self, deck_id: UUID) -> Deck:
        deck = await self.repo.get_by_id(deck_id)
        if not deck:
            raise HTTPException(status_code=404)  # HTTP leak!
        return deck

# GOOD: Service raises domain exception
from app.utils.exceptions import NotFoundError

class DeckService:
    async def get_deck(self, deck_id: UUID) -> Deck:
        deck = await self.repo.get_by_id(deck_id)
        if not deck:
            raise NotFoundError("Deck")  # domain exception
        return deck

# The translation happens once, globally:
@app.exception_handler(AppError)
async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": type(exc).__name__, "message": exc.message}},
    )
```

### Services Must Not Own the Session

```python
# BAD: Service creates its own session
class DeckService:
    async def create_deck(self, data: DeckCreate) -> Deck:
        async with async_session_factory() as db:
            deck = Deck(**data.model_dump())
            db.add(deck)
            await db.commit()  # commits immediately -- can't compose
            return deck

# GOOD: Session injected from outside
class DeckRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, data: DeckCreate, **extra) -> Deck:
        deck = Deck(**data.model_dump(), **extra)
        self.db.add(deck)
        await self.db.flush()  # within transaction, doesn't commit
        await self.db.refresh(deck)
        return deck

# Multiple repos in one request share the same session + transaction
@router.post("/clone")
async def clone_problem(body: CloneRequest, db: DbSession, user: CurrentUser):
    problem_repo = ProblemRepository(db)
    viz_repo = VisualizationRepository(db)
    # Both repos operate within the same transaction
    # If viz cloning fails, problem creation is rolled back too
    problem = await problem_repo.create(...)
    await viz_repo.clone_for_problem(original_id, problem.id)
    return problem
```

### When NOT to Use a Service

Don't wrap a single ActiveRecord/ORM call in a service just for architecture's sake.

```python
# OVER-ENGINEERED: Service adds nothing
class UserService:
    async def get_user(self, user_id: UUID) -> User:
        return await self.repo.get_by_id(user_id)

# FINE: Simple lookup directly in route
@router.get("/users/{user_id}")
async def get_user(user_id: UUID, db: DbSession) -> User:
    user = await db.get(User, user_id)
    if not user:
        raise NotFoundError("User")
    return user
```

Use a service when:
- There's business logic beyond CRUD
- Multiple repositories need to coordinate
- The operation has side effects (emails, webhooks, analytics)
- The logic needs to be tested independently of HTTP

### Cross-Service Operations

```python
# Services that need each other should share the same session
class CommunityService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.problem_repo = ProblemRepository(db)
        self.viz_repo = VisualizationRepository(db)

    async def clone_problem(self, problem_id: UUID, user_id: UUID) -> Problem:
        original = await self.problem_repo.get_by_id_or_raise(problem_id)
        cloned = await self.problem_repo.create(...)
        await self.viz_repo.clone_for_problem(original.id, cloned.id)
        return cloned
        # Both operations in same transaction -- atomic
```

---

## Error Handling

### Exception Hierarchy

```python
class AppError(Exception):
    """Base exception for all domain errors."""
    def __init__(self, message: str = "An error occurred", status_code: int = 500):
        self.message = message
        self.status_code = status_code
        super().__init__(self.message)

class NotFoundError(AppError):
    def __init__(self, resource: str = "Resource"):
        super().__init__(f"{resource} not found", status_code=404)

class AuthenticationError(AppError):
    def __init__(self, message: str = "Authentication failed"):
        super().__init__(message, status_code=401)

class AuthorizationError(AppError):
    def __init__(self, message: str = "Insufficient permissions"):
        super().__init__(message, status_code=403)

class ValidationError(AppError):
    def __init__(self, message: str = "Validation failed"):
        super().__init__(message, status_code=400)

class ConflictError(AppError):
    def __init__(self, message: str = "Conflict"):
        super().__init__(message, status_code=409)

class ExternalServiceError(AppError):
    def __init__(self, service: str, message: str = ""):
        super().__init__(f"{service} error: {message}", status_code=502)
```

### Global Exception Handlers

```python
def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={"error": {"code": type(exc).__name__, "message": exc.message}},
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        # Stringify non-serializable context values
        safe_errors = []
        for err in exc.errors():
            safe_err = {**err}
            if "ctx" in safe_err:
                safe_err["ctx"] = {k: str(v) for k, v in safe_err["ctx"].items()}
            safe_errors.append(safe_err)
        return JSONResponse(
            status_code=422,
            content={"error": {
                "code": "ValidationError",
                "message": "Request validation failed",
                "detail": safe_errors,
            }},
        )

    @app.exception_handler(Exception)
    async def handle_unhandled(request: Request, exc: Exception) -> JSONResponse:
        logger.error("unhandled_exception", exc_info=exc)
        return JSONResponse(
            status_code=500,
            content={"error": {"code": "InternalServerError", "message": "Internal server error"}},
        )
```

### HTTPException in Middleware Does NOT Hit Exception Handlers

```python
# WRONG: This HTTPException won't be caught by @app.exception_handler
@app.middleware("http")
async def my_middleware(request: Request, call_next):
    raise HTTPException(status_code=401)  # NOT caught by handlers!

# The middleware stack is:
#   ServerErrorMiddleware -> Custom Middleware -> ExceptionMiddleware -> Router
# Exception handlers live in ExceptionMiddleware, but custom middleware sits ABOVE it.

# RIGHT: Return JSONResponse directly in middleware
@app.middleware("http")
async def my_middleware(request: Request, call_next):
    return JSONResponse(
        status_code=401,
        content={"error": {"code": "Unauthorized", "message": "..."}},
    )
```

### Consistent Error Envelope

Every error response follows the same shape:

```json
{
  "error": {
    "code": "NotFoundError",
    "message": "Deck not found",
    "detail": null
  }
}
```

This includes Pydantic validation errors, domain errors, and unhandled exceptions. The frontend always checks `response.error.message` -- never different shapes for different error types.

---

## Authentication & Authorization

### Dependencies Over Middleware for Auth

```python
# Auth dependency -- the canonical FastAPI pattern
bearer_scheme = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    payload = decode_token(credentials.credentials)
    user_id = payload.get("sub")
    if not user_id:
        raise AuthenticationError("Invalid token")

    result = await db.execute(select(User).where(User.id == UUID(user_id)))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        raise AuthenticationError("User not found or inactive")
    return user
```

**Why dependencies, not middleware:**
1. Type-safe: returns `User`, not `request.state.user`
2. Only runs on routes that need it (no whitelist)
3. Composes: `require_role` chains on `get_current_user`
4. FastAPI caches per request (multiple deps calling `get_current_user` resolve it once)

### Parameterized Role Dependencies

```python
def require_role(*roles: UserRole) -> Callable[..., Awaitable[User]]:
    async def checker(user: User = Depends(get_current_user)) -> User:
        if user.role not in roles:
            raise AuthorizationError("Insufficient permissions")
        return user
    return checker

# Usage
@router.delete("/users/{user_id}")
async def delete_user(user: User = Depends(require_role(UserRole.ADMIN))):
    ...
```

### JWT Token Pair Pattern

```python
def create_access_token(user_id: UUID) -> str:
    expire = datetime.now(UTC) + timedelta(minutes=30)
    payload = {"sub": str(user_id), "exp": expire, "type": "access"}
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")

def create_refresh_token(user_id: UUID) -> str:
    expire = datetime.now(UTC) + timedelta(days=7)
    payload = {"sub": str(user_id), "exp": expire, "type": "refresh"}
    return jwt.encode(payload, settings.secret_key, algorithm="HS256")

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.secret_key, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise AuthenticationError("Token expired")
    except jwt.PyJWTError:
        raise AuthenticationError("Invalid token")
```

**Important: Token type validation.** Always check `payload["type"]` matches the expected type. Without this, a refresh token can be used as an access token.

---

## Pagination

### Offset-Limit with Dependency

```python
from fastapi import Query

class PaginationParams:
    def __init__(
        self,
        page: int = Query(1, ge=1),
        limit: int = Query(20, ge=1, le=250),
    ):
        self.page = page
        self.limit = limit
        self.offset = (page - 1) * limit

class PaginatedResponse(BaseModel, Generic[T]):
    items: list[T]
    total: int
    page: int
    limit: int
    has_more: bool

    @classmethod
    def create(cls, *, items: list, total: int, page: int, limit: int):
        return cls(
            items=items, total=total, page=page, limit=limit,
            has_more=(page * limit) < total,
        )
```

### When to Consider Cursor-Based Pagination

Offset pagination is O(n) for deep pages (`OFFSET 10000` scans and discards 10,000 rows).

Consider cursor-based pagination when:
- Users can scroll through 1,000+ items
- You have an activity feed or timeline
- Response time degrades noticeably on page 50+

```python
# Cursor-based: WHERE (created_at, id) < (cursor_values) ORDER BY created_at DESC, id DESC
# Constant time regardless of page depth
# But: no random page access, no total count
```

For most apps (decks, problem lists, admin tables), offset pagination is fine.

---

## Background Jobs

### Decision Matrix

| Criteria | `BackgroundTasks` | `arq` / `SAQ` | Celery |
|----------|-------------------|---------------|--------|
| Survives server crash | No | Yes (Redis) | Yes |
| Retry with backoff | No | Yes | Yes |
| Status tracking | No | Yes | Yes |
| Separate process | No | Yes | Yes |
| Setup complexity | None | Low | High |
| Best for | Fire-and-forget (emails, logging) | Async I/O (LLM calls, webhooks) | CPU-heavy, distributed |

### When to Use BackgroundTasks

```python
@router.post("/users", status_code=201)
async def create_user(data: UserCreate, background_tasks: BackgroundTasks):
    user = await service.create(data)
    # Fire-and-forget: if email fails, user is still created
    background_tasks.add_task(send_welcome_email, user.email)
    return user
```

### When to Use a Job Queue

```python
# Long-running, needs retry, needs status tracking
@router.post("/visualizations/generate")
async def generate_viz(data: GenerateRequest, user: CurrentUser):
    job = await redis_pool.enqueue_job(
        "generate_visualization",
        data.model_dump(),
        _job_id=f"viz-{user.id}-{uuid4()}",
    )
    return {"job_id": job.job_id, "status": "queued"}
```

### Idempotent Job Design

```python
# BAD: Not idempotent -- retries create duplicates
async def process_payment(ctx, order_id: str):
    order = await get_order(order_id)
    await charge_card(order.amount)  # retried = double charge!
    order.status = "paid"
    await save(order)

# GOOD: Check-before-act pattern
async def process_payment(ctx, order_id: str):
    order = await get_order(order_id)
    if order.status == "paid":
        return  # already processed, skip
    await charge_card(order.amount, idempotency_key=order_id)
    order.status = "paid"
    await save(order)
```

---

## Testing

### Test Database Setup

```python
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.pool import NullPool

TEST_DATABASE_URL = "postgresql+asyncpg://postgres:postgres@localhost:5432/myapp_test"

# NullPool: no connection pooling in tests -- prevents leaks between tests
test_engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
test_session = async_sessionmaker(test_engine, class_=AsyncSession, expire_on_commit=False)

@pytest.fixture(autouse=True)
async def setup_db():
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
```

### Dependency Override for Tests

```python
@pytest.fixture
async def client():
    async def override_get_db():
        async with test_session() as session:
            try:
                yield session
                await session.commit()
            except Exception:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test",
    ) as ac:
        yield ac

    app.dependency_overrides.clear()  # ALWAYS clean up
```

### Test Fixture Pattern

```python
@pytest.fixture
async def test_user(db: AsyncSession) -> User:
    user = User(
        id=uuid4(),
        email="test@example.com",
        github_id="12345",
        github_username="testuser",
        role=UserRole.USER,
        is_active=True,
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user

@pytest.fixture
async def auth_headers(test_user: User) -> dict:
    token = create_access_token(test_user.id)
    return {"Authorization": f"Bearer {token}"}
```

### Unit Tests: Mock the Session, Not the Service

```python
# Test business logic without touching HTTP or database
@pytest.mark.asyncio
async def test_deck_service_rejects_duplicate_problem():
    mock_db = AsyncMock(spec=AsyncSession)
    # Simulate existing deck_problem
    mock_db.execute.return_value = MagicMock(
        scalar_one_or_none=MagicMock(return_value=existing_deck_problem)
    )

    with pytest.raises(ConflictError, match="already in deck"):
        await add_problem_to_deck(mock_db, deck_id, problem_id)
```

### Integration Tests: Hit the Real Stack

```python
@pytest.mark.asyncio
async def test_create_deck(client: AsyncClient, auth_headers: dict):
    response = await client.post(
        "/api/decks",
        json={"title": "Arrays", "description": "Array problems"},
        headers=auth_headers,
    )
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Arrays"
    assert "id" in data
```

### Test Error Paths, Not Just Happy Paths

```python
@pytest.mark.asyncio
async def test_get_deck_not_found(client: AsyncClient, auth_headers: dict):
    response = await client.get(f"/api/decks/{uuid4()}", headers=auth_headers)
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "NotFoundError"

@pytest.mark.asyncio
async def test_create_deck_unauthorized(client: AsyncClient):
    response = await client.post("/api/decks", json={"title": "Test"})
    assert response.status_code == 403  # No auth header
```

---

## Database Migrations

### Review Autogenerated Migrations

Alembic autogenerate produces false positives:
- Dropping and recreating indexes that haven't changed
- Reordering columns
- Recreating enum types

**Always read every migration before running it.** Delete the noise.

### Enum Types: Always Raw SQL

```python
# BAD: sa.Enum.create() in migration
def upgrade():
    sa.Enum("easy", "medium", "hard", name="difficulty").create(op.get_bind())

# GOOD: Raw SQL with existence check (idempotent)
def upgrade():
    op.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'difficulty')
            THEN CREATE TYPE difficulty AS ENUM ('easy', 'medium', 'hard');
            END IF;
        END $$
    """)
```

### Adding Values to an Existing Enum

```python
# PostgreSQL doesn't support IF NOT EXISTS for ALTER TYPE ADD VALUE until v12
# Use this pattern:
def upgrade():
    op.execute("""
        DO $$ BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_enum
                WHERE enumlabel = 'ruby'
                AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'language')
            ) THEN
                ALTER TYPE language ADD VALUE 'ruby';
            END IF;
        END $$
    """)
```

### Never Hardcode Revision IDs

Let Alembic generate unique revision IDs. Copying from examples or other migrations causes conflicts.

```bash
# ALWAYS generate fresh
alembic revision --autogenerate -m "add language column"
# Never copy revision = "abc123" from another file
```

### Test Migrations Both Ways

1. Against a clean database (from scratch)
2. Against current production state (incremental)

A migration that works from scratch but fails on production data (or vice versa) will bite you on deploy.

---

## Configuration

### Pydantic BaseSettings with Production Validation

```python
from pydantic_settings import BaseSettings, SettingsConfigDict

_WEAK_SECRET = "dev-secret-change-me"

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env",),
        case_sensitive=False,
    )

    # App
    debug: bool = False
    cors_origins: str = "http://localhost:3000"

    # Database
    database_url: str = "postgresql+asyncpg://localhost/myapp"

    # Auth
    secret_key: str = _WEAK_SECRET
    access_token_expire_minutes: int = 30

    # Pool
    db_pool_size: int = 5
    db_pool_recycle: int = 1800  # 30 min

    @model_validator(mode="after")
    def enforce_production(self) -> "Settings":
        if not self.debug and self.secret_key == _WEAK_SECRET:
            raise ValueError("SECRET_KEY must be set in production")
        # Auto-convert Render's postgresql:// to asyncpg
        if self.database_url.startswith("postgresql://"):
            self.database_url = self.database_url.replace(
                "postgresql://", "postgresql+asyncpg://", 1
            )
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",")]

settings = Settings()
```

### Engine Configuration for PaaS

```python
engine = create_async_engine(
    settings.database_url,
    pool_pre_ping=True,        # verify connections before use
    pool_size=5,                # match your plan's connection limit
    max_overflow=5,
    pool_timeout=30,
    pool_recycle=1800,          # recycle connections every 30 min
    connect_args={
        "server_settings": {"statement_timeout": "30000"}  # 30s query timeout
    },
)
```

---

## Concurrency & Locking

### with_for_update() for Serialized Access

See [Row-Level Locking](#row-level-locking-for-concurrent-safety) above.

Use when:
- Multiple requests can modify the same parent (e.g., adding items to a deck)
- Position/ordering needs to be sequential
- You need to read-then-write atomically

Don't use when:
- Reads only (no locking needed)
- Low contention (personal projects with single-user access)

### Atomic Counter Updates

```python
# BAD: Read-modify-write race condition
problem = await db.get(Problem, problem_id)
problem.clone_count += 1  # another request could read the old value

# GOOD: Atomic increment in SQL
from sqlalchemy import update

stmt = (
    update(Problem)
    .where(Problem.id == problem_id)
    .values(clone_count=Problem.clone_count + 1)
)
await db.execute(stmt)
```

---

## Quick Reference

| Mistake | Fix |
|---------|-----|
| `expire_on_commit=True` (default) | Set `expire_on_commit=False` on async sessionmaker |
| Lazy loading relationships in async | Use `selectinload`/`joinedload` explicitly |
| `commit()` inside service methods | Use `flush()` in services, `commit()` at request boundary |
| `HTTPException` in services | Raise domain exceptions (`NotFoundError`, etc.) |
| `SELECT *` on list endpoints | Select specific columns, exclude TEXT fields |
| `ORDER BY random()` for queues | Pre-compute priority, or use offset-based sampling |
| Hardcoded enum creation in migrations | Raw SQL with `IF NOT EXISTS` |
| `sa.Enum.create()` in Alembic | Raw SQL always |
| `any` in Pydantic field types | Use `unknown` patterns or specific union types |
| Default values not validated | Set `validate_default=True` in `model_config` |
| Session shared across `asyncio.gather` | One session per concurrent task |
| `HTTPException` in middleware | Return `JSONResponse` directly |
| Mutable default arguments | Use `Field(default_factory=list)` not `Field(default=[])` |
| Route handles business logic | Extract to service layer |
| Missing error path tests | Test 404, 401, 403, 422 alongside happy paths |

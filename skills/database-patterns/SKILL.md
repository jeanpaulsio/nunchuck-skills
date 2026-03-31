---
name: database-patterns
description: Deep reference for PostgreSQL schema design, query optimization, indexing, migration safety, and data modeling. Focused on patterns that prevent costly refactors.
---

# Database Patterns

Production patterns for PostgreSQL schema design, query optimization, and migration discipline. These patterns apply regardless of your ORM (SQLAlchemy, ActiveRecord, Prisma, raw SQL).

---

## Table of Contents

1. [Schema Design Principles](#schema-design-principles)
2. [Data Modeling Decisions](#data-modeling-decisions)
3. [Indexing Strategy](#indexing-strategy)
4. [Query Optimization](#query-optimization)
5. [Migration Safety](#migration-safety)
6. [Enum Patterns](#enum-patterns)
7. [Soft Delete](#soft-delete)
8. [Audit Logging](#audit-logging)
9. [Connection Management](#connection-management)
10. [Quick Reference](#quick-reference)

---

## Schema Design Principles

### One Concern Per Table

If a table serves two masters, the queries for both get slower and the code gets tangled.

**Smell:** Groups of columns that always get updated together but independently from other groups.

```
-- BAD: Problem table mixing content and review state
problems
├── id, title, slug, description        -- content (read often, updated rarely)
├── solution_code, starter_code         -- content (large TEXT, updated rarely)
├── ease_factor, review_interval        -- review state (updated every practice)
├── repetitions, next_review_at         -- review state
└── review_uncertainty                  -- review state

-- Every list query carries review state it doesn't need
-- Every review query carries content columns it doesn't need
```

```
-- GOOD: Separate concerns
problems
├── id, title, slug, description, solution_code, starter_code

problem_review_states
├── problem_id (FK), ease_factor, review_interval, repetitions, next_review_at
```

**When to split:** When you feel the pain, not before. Two instances of awkward queries is a coincidence. Three is a pattern worth extracting.

### Domain Names, Not UI Names

Column names describe what the data IS, not how it's DISPLAYED.

```
Good:  title, scheduled_at, status, difficulty, position
Bad:   card_title, calendar_display_date, sidebar_status, dropdown_difficulty
```

**Test:** If you rename a UI element, would you need to rename a column? If yes, the column name leaks presentation.

### Status Enums, Not Boolean Soup

```sql
-- BAD: Boolean soup creates impossible states
ALTER TABLE jobs ADD COLUMN is_quoted BOOLEAN DEFAULT FALSE;
ALTER TABLE jobs ADD COLUMN is_accepted BOOLEAN DEFAULT FALSE;
ALTER TABLE jobs ADD COLUMN is_in_progress BOOLEAN DEFAULT FALSE;
ALTER TABLE jobs ADD COLUMN is_completed BOOLEAN DEFAULT FALSE;
ALTER TABLE jobs ADD COLUMN is_paid BOOLEAN DEFAULT FALSE;
-- Q: What does is_completed = true AND is_in_progress = true mean?

-- GOOD: One column, defined states
CREATE TYPE job_status AS ENUM ('lead', 'quoted', 'accepted', 'in_progress', 'completed', 'paid');
ALTER TABLE jobs ADD COLUMN status job_status NOT NULL DEFAULT 'lead';
-- Impossible to be completed AND in_progress simultaneously
```

### Timestamps on Everything

```sql
-- Mutable tables: both timestamps
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()

-- Append-only audit tables: only created_at (they never change)
created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
-- No updated_at -- audit records are immutable
```

### Nullable Foreign Keys for Optional Relationships

When a relationship is optional (e.g., a visualization MAY be linked to a problem):

```sql
-- Use nullable FK with SET NULL on delete
problem_id UUID REFERENCES problems(id) ON DELETE SET NULL
-- If the problem is deleted, the visualization keeps its other data
```

Cleaner than a join table for 0-or-1 relationships.

---

## Data Modeling Decisions

### UUID vs Integer Primary Keys

| | UUID | Integer |
|---|---|---|
| Globally unique | Yes | No |
| Client-side generation | Yes | No (needs DB roundtrip) |
| URL guessability | Low | High (enumerable) |
| Index size | 16 bytes | 4-8 bytes |
| Sort by creation order | No (use timestamp) | Yes (auto-increment) |

**Use UUIDs when:** User-facing IDs, distributed systems, API resources.
**Use integers when:** Internal join tables, high-volume analytics tables where index size matters.

### Join Table Design

```sql
-- Many-to-many with metadata
CREATE TABLE deck_problems (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    deck_id UUID NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
    problem_id UUID NOT NULL REFERENCES problems(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    section VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (deck_id, problem_id)  -- prevent duplicate membership
);

-- Index the foreign keys (PostgreSQL does NOT auto-index them)
CREATE INDEX idx_deck_problems_deck_id ON deck_problems(deck_id);
CREATE INDEX idx_deck_problems_problem_id ON deck_problems(problem_id);
```

### Partial Unique Indexes

When uniqueness only applies to a subset of rows:

```sql
-- Allow multiple empty slots per deck, but each problem can only appear once
CREATE UNIQUE INDEX uq_deck_slot_problem
    ON deck_slots(deck_id, problem_id)
    WHERE problem_id IS NOT NULL;
-- NULL values don't violate unique constraints in PostgreSQL
-- This prevents assigning the same problem to two slots in one deck
```

### JSONB for Semi-Structured Data

Use JSONB when the schema varies per row or changes frequently.

```sql
-- User preferences: structure varies by feature flags, user type, etc.
ai_model_preferences JSONB DEFAULT NULL

-- Query JSONB in PostgreSQL
SELECT * FROM users WHERE ai_model_preferences->>'default_model' = 'claude-sonnet';

-- Index JSONB for query performance
CREATE INDEX idx_user_preferences ON users USING GIN (ai_model_preferences);
```

**Don't use JSONB for:** Data you query frequently with WHERE clauses. If you're filtering by `preferences->>'theme'` in every request, it should be a column.

### When to Denormalize

**Default:** Don't. JOINs are what relational databases are built for.

**Denormalize when:**
1. You've measured a performance problem (not assumed one)
2. The JOIN is the bottleneck (not missing indexes, not N+1 queries)
3. The denormalized data rarely changes (or you accept the update anomaly risk)

**Common acceptable denormalization:**
- `clone_count` on a problem (counter cache, updated atomically with SQL)
- `problem_count` on a deck (only if the JOIN to count is measurably slow)

**Always use atomic SQL for counter updates:**
```sql
-- NOT read-modify-write (race condition)
-- YES: atomic increment
UPDATE problems SET clone_count = clone_count + 1 WHERE id = $1;
```

---

## Indexing Strategy

### Index Your WHERE Clauses

Look at your actual queries and index what they filter on.

```sql
-- Query: "My active problems ordered by creation date"
SELECT * FROM problems
WHERE user_id = $1 AND is_archived = FALSE
ORDER BY created_at DESC;

-- Index:
CREATE INDEX idx_problems_user_active ON problems(user_id, created_at DESC)
WHERE is_archived = FALSE;
-- Partial index: only indexes non-archived rows, smaller and faster
```

### Composite Index Column Order Matters

The leftmost column is the entry point. Put the most selective column first.

```sql
-- Query filters on user_id AND status
CREATE INDEX idx_problems_user_status ON problems(user_id, status);
-- This index serves:
--   WHERE user_id = $1 AND status = 'active'  ✓
--   WHERE user_id = $1                         ✓ (leftmost prefix)
--   WHERE status = 'active'                    ✗ (can't skip user_id)
```

### PostgreSQL Does NOT Auto-Index Foreign Keys

Unlike MySQL, PostgreSQL does not automatically create indexes on foreign key columns. You must add them manually.

```sql
-- After creating a FK, always add the index
ALTER TABLE deck_problems ADD COLUMN deck_id UUID REFERENCES decks(id);
CREATE INDEX idx_deck_problems_deck_id ON deck_problems(deck_id);
-- Without this index, DELETE FROM decks WHERE id = $1
-- does a sequential scan on deck_problems
```

### Don't Index Everything

Each index:
- Slows down INSERTs and UPDATEs (index must be maintained)
- Uses disk space
- Adds write amplification

**Index when:** A query is slow and EXPLAIN shows a sequential scan on a large table.
**Don't index:** Columns only used in SELECT (not WHERE/JOIN/ORDER BY), small tables (<1000 rows), boolean columns with low selectivity.

### Use EXPLAIN ANALYZE

```sql
EXPLAIN ANALYZE
SELECT * FROM problems
WHERE user_id = '...' AND is_archived = FALSE
ORDER BY created_at DESC
LIMIT 20;

-- Look for:
-- "Seq Scan" on large tables → needs an index
-- "Rows Removed by Filter: 50000" → index not selective enough
-- "Sort Method: external merge" → needs index on ORDER BY column
```

---

## Query Optimization

### Explicit Column Selection for Lists

TEXT columns live in PostgreSQL's TOAST tables. Fetching them in bulk is expensive.

```sql
-- BAD: Select everything including 5 TEXT columns
SELECT * FROM problems WHERE user_id = $1;

-- GOOD: Select only what the list view needs
SELECT id, title, slug, difficulty, language, tags, created_at
FROM problems WHERE user_id = $1;

-- Save the TEXT columns (description, solution_code, starter_code,
-- test_suite, editorial) for the detail view
```

### Don't Use ORDER BY random()

```sql
-- BAD: Full table scan, every single time
SELECT * FROM problems
WHERE next_review_at <= NOW()
ORDER BY random()
LIMIT 1;

-- BETTER: Random offset (two queries but index-friendly)
SELECT COUNT(*) FROM problems WHERE next_review_at <= NOW();
-- Then:
SELECT * FROM problems
WHERE next_review_at <= NOW()
OFFSET floor(random() * count)
LIMIT 1;

-- BEST: Pre-compute a review_priority column, index it
```

### N+1 Query Detection

The most common performance problem in ORM-based applications.

```python
# BAD: N+1 queries
decks = await db.execute(select(Deck).where(Deck.user_id == user_id))
for deck in decks:
    problems = deck.problems  # each access fires a query!

# GOOD: Eager load in one query
decks = await db.execute(
    select(Deck)
    .where(Deck.user_id == user_id)
    .options(selectinload(Deck.problems))
)
```

**In development, use `lazy="raise"` to catch N+1s immediately:**
```python
class Deck(Base):
    problems: Mapped[list[Problem]] = relationship(lazy="raise")
    # Accessing deck.problems without eager loading now raises instead of silently querying
```

### Aggregate Subqueries Over Separate Queries

```sql
-- BAD: One query for decks, then N queries for counts
SELECT * FROM decks WHERE user_id = $1;
-- For each deck: SELECT COUNT(*) FROM deck_problems WHERE deck_id = $deck_id;

-- GOOD: One query with subquery
SELECT d.*,
    COALESCE(pc.problem_count, 0) AS problem_count
FROM decks d
LEFT JOIN (
    SELECT deck_id, COUNT(*) AS problem_count
    FROM deck_problems
    GROUP BY deck_id
) pc ON d.id = pc.deck_id
WHERE d.user_id = $1;
```

---

## Migration Safety

### Review Autogenerated Migrations

Migration generators produce false positives:
- Dropping and recreating indexes that haven't changed
- Reordering columns
- Recreating enum types
- Adding/removing indexes on unrelated tables

**Always read every migration before running it.** Delete the noise.

### Never Edit an Applied Migration

Once a migration has run (locally, in CI, or in prod), it is immutable. If you need to fix something, write a new migration on top. Editing an applied migration causes schema drift: the database ran the old version, the file now says something different, and `upgrade head` is a no-op because it thinks the migration already ran.

### Dangerous Operations: Lock Awareness

Some DDL operations lock the entire table. On a busy table, this means downtime.

```sql
-- LOCKS THE TABLE (blocks all reads and writes):
ALTER TABLE problems ADD COLUMN foo VARCHAR(255) NOT NULL DEFAULT 'bar';
-- On Postgres < 11, this rewrites the entire table

-- DOES NOT LOCK (on Postgres 11+):
ALTER TABLE problems ADD COLUMN foo VARCHAR(255) DEFAULT 'bar';
-- Nullable column with default is instant (metadata-only change)

-- SAFE pattern for NOT NULL with default:
-- Step 1: Add nullable column with default (instant)
ALTER TABLE problems ADD COLUMN foo VARCHAR(255) DEFAULT 'bar';
-- Step 2: Backfill existing rows (in batches, not one big UPDATE)
UPDATE problems SET foo = 'bar' WHERE foo IS NULL;
-- Step 3: Add NOT NULL constraint
ALTER TABLE problems ALTER COLUMN foo SET NOT NULL;
```

### Never Hardcode Revision IDs

Let your migration tool generate unique IDs. Copying from examples causes conflicts.

### Test Migrations Both Ways

1. Against a clean database (does CREATE TABLE work?)
2. Against current production state (does ALTER TABLE work?)

---

## Enum Patterns

### Always Raw SQL in Migrations

```python
# BAD: ORM-level enum creation
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

```sql
-- Check before adding (idempotent)
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'ruby'
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'language')
    ) THEN
        ALTER TYPE language ADD VALUE 'ruby';
    END IF;
END $$;
```

### Column Reference with create_type=False

When using enums in `create_table`:

```python
op.create_table(
    "problems",
    sa.Column("difficulty", sa.Enum("easy", "medium", "hard", name="difficulty", create_type=False)),
    # create_type=False: the enum already exists from the DO $$ block above
)
```

---

## Soft Delete

### deleted_at Over is_deleted

```sql
-- BAD: Boolean -- you only know IF, not WHEN
ALTER TABLE problems ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;

-- GOOD: Timestamp -- you know IF and WHEN
ALTER TABLE problems ADD COLUMN deleted_at TIMESTAMPTZ DEFAULT NULL;
-- NULL = active, non-NULL = deleted at that timestamp
```

### Gotchas

1. **Every query must filter.** Miss one `WHERE deleted_at IS NULL` and you leak deleted data.
2. **Unique constraints break.** Soft-delete "two-sum" slug, create new "two-sum" -- unique violation. Fix: compound unique on `(slug, deleted_at)` or use a partial unique index.
3. **Cascade doesn't fire.** SQLAlchemy `cascade="all, delete"` only fires on hard deletes. Soft-deleted parents still have visible children.
4. **COUNT(*) includes deleted rows** unless filtered.

### Prefer Hard Delete Unless You Have a Reason

Soft delete adds complexity to every query. Only use it when you genuinely need:
- Undo/restore functionality
- Regulatory data retention
- Audit trail requirements

For most resources, hard delete is simpler and correct.

---

## Audit Logging

### Append-Only Audit Table

```sql
CREATE TABLE audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name VARCHAR(255) NOT NULL,
    record_id UUID NOT NULL,
    action VARCHAR(10) NOT NULL,  -- 'insert', 'update', 'delete'
    changes JSONB,                 -- {field: {old: x, new: y}}
    user_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    -- NO updated_at: audit records are immutable
);

CREATE INDEX idx_audit_log_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);
```

### Write Audit Logs in the Same Transaction

```python
# Audit log is written in the same transaction as the data change.
# If the transaction rolls back, the audit log rolls back too.
# No phantom audit entries.

async def update_problem(db: AsyncSession, problem: Problem, data: ProblemUpdate):
    changes = {}
    update_data = data.model_dump(exclude_unset=True)
    for field, new_value in update_data.items():
        old_value = getattr(problem, field)
        if old_value != new_value:
            changes[field] = {"old": str(old_value), "new": str(new_value)}
            setattr(problem, field, new_value)

    if changes:
        db.add(AuditLog(
            table_name="problems",
            record_id=problem.id,
            action="update",
            changes=changes,
            user_id=problem.user_id,
        ))
    await db.flush()
```

---

## Connection Management

### Pool Configuration for PaaS

```python
engine = create_async_engine(
    database_url,
    pool_pre_ping=True,     # verify connections before use
    pool_size=5,             # match your plan's connection limit
    max_overflow=5,          # burst capacity
    pool_timeout=30,         # wait 30s for a connection before failing
    pool_recycle=1800,       # recycle connections every 30 min (prevent stale)
    connect_args={
        "server_settings": {"statement_timeout": "30000"}  # 30s query timeout
    },
)
```

**pool_pre_ping:** Sends a lightweight query before each connection use. Catches connections that were closed by the server (idle timeout, restart). Small overhead, prevents "connection closed" errors.

**pool_recycle:** PaaS platforms (Render, Heroku, Railway) kill idle connections. Recycling before the platform's timeout prevents "server closed the connection unexpectedly" errors.

**statement_timeout:** Prevents runaway queries from holding connections indefinitely. 30 seconds is reasonable for a web app.

### NullPool for Tests

```python
from sqlalchemy.pool import NullPool

test_engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
# No pooling = no connection leaks between tests
# Each test gets a fresh connection
```

---

## Quick Reference

| Mistake | Fix |
|---------|-----|
| Boolean soup (`is_active`, `is_completed`, `is_paid`) | Single status enum column |
| UI names in columns (`card_title`, `sidebar_label`) | Domain names (`title`, `label`) |
| `SELECT *` on list endpoints | Explicit column selection |
| Missing FK indexes | Always index foreign keys manually |
| `ORDER BY random()` | Offset-based sampling or priority column |
| `sa.Enum.create()` in migrations | Raw SQL with `IF NOT EXISTS` |
| Denormalizing "to avoid JOINs" | JOINs are fine; index the join columns |
| Soft delete by default | Hard delete unless you need undo/audit/regulatory |
| `NOT NULL DEFAULT 'x'` on large tables | Add nullable with default, backfill, then add NOT NULL |
| Counter cache with read-modify-write | Atomic SQL: `SET count = count + 1` |
| No `pool_pre_ping` | Stale connections crash on PaaS |
| No `statement_timeout` | Runaway queries hold connections forever |

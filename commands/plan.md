---
description: Product thinking + systems design before writing code. Walks through requirements, schema design, API contracts, and implementation roadmap.
---

# Plan

Before writing any code, work through these phases. Skip phases that don't apply (bug fixes and refactors can skip straight to the implementation plan).

## 1. Scout (if unfamiliar codebase)

Use the **codebase-assessor** agent to understand the current state. Skip if you already know the codebase well.

## 2. Product Think (new features or new projects)

Use the **product-thinker** agent to extract requirements through conversation:
- Draw out the nouns, relationships, state transitions, and edge cases
- Define v1 scope and what to defer
- Summarize in the user's language, not engineering jargon
- WAIT for user confirmation before proceeding to design

## 3. Design

This is where ideas become architecture. Present each section and get confirmation before moving on.

### Schema Design

For each noun from Product Think, define the table:
- Column names use domain language (not UI language)
- Lifecycles become a single status enum (not boolean soup)
- Foreign keys for relationships, with cascade rules
- Timestamps on everything (`created_at`, `updated_at`)
- Call out which columns are nullable vs required
- Note any indexes needed for common queries

Present the schema as a clear table-by-table breakdown:

```
Table: bookings
  id            UUID, PK
  customer_id   UUID, FK -> customers, NOT NULL, INDEX
  time_slot_id  UUID, FK -> time_slots, NOT NULL
  status        ENUM (reserved, paid, active, returned, damaged), NOT NULL, DEFAULT 'reserved'
  deposit_paid  BOOLEAN, NOT NULL, DEFAULT false
  created_at    TIMESTAMPTZ, NOT NULL
  updated_at    TIMESTAMPTZ, NOT NULL

  Indexes: (customer_id), (time_slot_id), (status) WHERE status IN ('reserved', 'paid')
  Constraints: UNIQUE (time_slot_id) -- one booking per slot
```

### API Contracts

For each resource, define the endpoints with request/response shapes:
- Consistent error envelope: `{ "error": { "code": "...", "message": "..." } }`
- Pagination on list endpoints (page/limit with total count)
- What fields are required vs optional on create/update
- What fields are returned on list vs detail views (list views exclude heavy TEXT fields)

### Service Boundaries

- One service per major domain concept
- Which operations are simple CRUD vs need business logic
- Where do cross-service operations happen (e.g., cloning a resource that has related records)
- What needs to be async (background jobs) vs synchronous

### Frontend Architecture (if applicable)

- Page structure and routing
- Which pages need what data
- Where does client state live vs server state (React Query)
- Mobile considerations (does this need a different layout on small screens?)

WAIT for user approval of the design before proceeding.

## 4. Implementation Plan

Break the approved design into an ordered roadmap. For each step:

```
Step 1: Create bookings migration and model
  Files: server/app/models/booking.py, alembic revision
  Dependencies: customers and time_slots tables must exist
  Tests: model validation tests
  Risk: enum type creation needs raw SQL, not sa.Enum.create()

Step 2: Build booking service
  Files: server/app/services/booking_service.py
  Dependencies: Step 1
  Tests: unit tests for create, cancel, return flows + error paths
  Risk: concurrent bookings on same time slot need row locking

Step 3: Add API routes
  Files: server/app/api/bookings.py, register in router.py
  Dependencies: Step 2
  Tests: integration tests for each endpoint (happy + error paths)
  Risk: none

Step 4: Frontend booking page
  Files: web/pages/app/bookings/+Page.tsx, web/services/bookings.ts
  Dependencies: Step 3
  Tests: component tests with mocked API
  Risk: calendar UI component selection -- research before hand-rolling
```

For each step, flag:
- **What could go wrong** and how to mitigate it
- **What touches shared code** (migrations, core models, auth, layout)
- **Whether this step should be its own PR** or grouped with others

Estimate overall scope: is this a 1-PR feature or a multi-PR effort?

WAIT for user CONFIRM before writing any code.

---

**For refactors and bug fixes** where product thinking and schema design aren't needed: skip to the implementation plan. Still break it down, still identify risks, still wait for confirmation.

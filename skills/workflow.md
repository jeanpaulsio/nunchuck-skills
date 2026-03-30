---
name: workflow
description: 5-phase engineering workflow - assess, product think, design, build, audit. The backbone of how features go from idea to shipped.
---

# Workflow

Five phases that take you from "I have an idea" to "it's shipped and I'm confident." Move through them in order, but jump back when new information surfaces.

## Phase 1: Assess

**When:** Starting work on any codebase, new or existing.

**Existing codebase:** Use the `/scout` command or **codebase-assessor** agent. Investigate stack, schema, tests, churn, and deployment constraints before suggesting anything.

**Greenfield:** Ask about experience, preferences, deployment target, and expected scale. Recommend a stack that plays to their strengths.

**Exit:** You can describe the codebase in 3-4 sentences and the user agrees.

## Phase 2: Product Think

**When:** Before writing any code for a new feature or project.

Use the **product-thinker** agent. This is a conversation, not a form. The user talks about their idea. The system extracts nouns, relationships, states, and edge cases through natural questions.

**Exit:** Nouns, relationships, lifecycles, v1 scope, and deferred items are captured. The user recognizes their own words in the summary.

## Phase 3: Design

**When:** After Product Think produces a clear picture.

Translate the summary into engineering decisions:
- Nouns become tables
- Relationships become foreign keys
- Lifecycles become status enums (not boolean soup)
- Column names use domain language (not UI language)
- API contracts defined (error envelope, pagination, endpoints)
- Service boundaries identified

Use the `/data-review` command to validate schema decisions against the database patterns skill.

**Exit:** Every table, its columns, its relationships, and the main API endpoints are defined. User confirms.

## Phase 4: Build

**When:** After Design produces a clear plan.

### Implementation Order

New feature: migration -> model -> service -> route -> frontend

Bug fix: write a failing test that reproduces the bug FIRST, then fix it.

### Testing (How We Actually Do It)

Strict TDD (red-green-refactor on every feature) sounds good in theory. In practice, here's what actually works:

**Bug fixes: test first.** Write a failing test that proves the bug exists. Then fix it. Then verify the test passes. This is the one place strict TDD pays for itself every time.

**New features: test alongside.** Build the feature, write tests as you go or immediately after each piece. Don't save testing for a separate sprint. A test backfill is a sign this step was skipped, and the fix-to-feat ratio will show it.

**Refactoring: tests must exist before you start.** If there are no tests for the code you're refactoring, write them first. Then refactor. Then verify they still pass.

The goal is not test-first purity. The goal is that tests exist when the feature ships, not two weeks later in a backfill sprint.

### Pre-Commit

Run the stack-specific checklist and reviewer before every commit:

```
/python-review    (Python projects)
/react-review     (React/TypeScript projects)
/rails-review     (Rails projects)
```

**Exit:** Tests pass, linter is clean, reviewer approves.

### Git

Branch and PR always. Never push to main. Conventional commits (`feat:`, `fix:`, `refactor:`). See `rules/git-workflow.md` for details.

## Phase 5: Audit

**When:** Ongoing, on cadence.

Use the `/audit` command with a frequency: daily, weekly, or monthly.

See the **ship-confident** skill for the full checklist at each cadence.

**Exit:** Findings ranked and either fixed inline (daily), ticketed (weekly), or added to sprint planning (monthly).

## Phase Transitions

- **Assess -> Product Think:** When you understand the landscape
- **Product Think -> Design:** When nouns, relationships, and v1 scope are clear
- **Design -> Build:** When schema and API contracts are defined
- **Build -> Audit:** Continuously, on cadence
- **Any -> Product Think:** When a new requirement changes the data model
- **Any -> Assess:** When switching to a new codebase

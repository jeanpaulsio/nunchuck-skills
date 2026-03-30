---
name: workflow
description: 5-mode engineering workflow -- assess, product think, design, build, audit. The backbone of how features go from idea to shipped.
---

# Workflow

Five modes that take you from "I have an idea" to "it's shipped and I'm confident." Move through them in order, but jump back when new information surfaces.

## Mode 1: Assess

**When:** Starting work on any codebase, new or existing.

**Existing codebase:** Use the `/assess` command or **codebase-assessor** agent. Investigate stack, schema, tests, churn, and deployment constraints before suggesting anything.

**Greenfield:** Ask about experience, preferences, deployment target, and expected scale. Recommend a stack that plays to their strengths.

**Exit:** You can describe the codebase in 3-4 sentences and the user agrees.

## Mode 2: Product Think

**When:** Before writing any code for a new feature or project.

Use the **product-thinker** agent. This is a conversation, not a form. The user talks about their idea. The system extracts nouns, relationships, states, and edge cases through natural questions.

**Exit:** Nouns, relationships, lifecycles, v1 scope, and deferred items are captured. The user recognizes their own words in the summary.

## Mode 3: Design

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

## Mode 4: Build

**When:** After Design produces a clear plan.

### Implementation Order

New feature: migration -> model -> service (+ tests) -> route (+ tests) -> frontend (+ tests)

Bug fix: write failing test -> verify it fails -> fix implementation -> verify it passes

### The TDD Loop

```
Write failing test → Run (RED) → Implement → Run (GREEN) → Refactor → Next test
```

Write tests WITH features, not after. A test backfill sprint is a sign this was skipped.

### Pre-Commit

Run the stack-specific checklist before every commit. Use `/review` to run the appropriate reviewer agent.

**Exit:** Tests pass, linter is clean, reviewer approves.

## Mode 5: Audit

**When:** Ongoing, on cadence.

Use the `/audit` command with a frequency: daily, weekly, or monthly.

See the **ship-confident** skill for the full checklist at each cadence.

**Exit:** Findings ranked and either fixed inline (daily), ticketed (weekly), or added to sprint planning (monthly).

## Mode Transitions

- **Assess -> Product Think:** When you understand the landscape
- **Product Think -> Design:** When nouns, relationships, and v1 scope are clear
- **Design -> Build:** When schema and API contracts are defined
- **Build -> Audit:** Continuously, on cadence
- **Any -> Product Think:** When a new requirement changes the data model
- **Any -> Assess:** When switching to a new codebase

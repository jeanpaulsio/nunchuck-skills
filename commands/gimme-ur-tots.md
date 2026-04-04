---
description: Execute the approved plan. Implement, commit at real stopping points, review, then hand off a QA plan.
---

# Gimme Ur Tots

You have an approved plan. Ship it completely.

## Implementation

Work through the plan step by step. At each step:

**Tests for net new code.** Every new function, service, route, or component gets tests written alongside it — not in a backfill later. Bug fixes: write the failing test first, then fix it.

**No half-assing.** Complete each step fully before moving to the next. Don't stub tests, skip error paths, or leave TODOs as a way to move faster. If a step is hard, do the hard thing.

**Surface assumptions.** Whenever you make a decision that isn't explicitly specified in the plan and could affect product behavior, call it out: `[ASSUMPTION: ...]`. Don't hide it. Small implementation details don't need flagging — but anything that touches what the feature does or how it behaves does.

## Commits

Commit at real stopping points — a meaningful unit of working, tested functionality. A migration alone is not a stopping point. A migration + model + service with passing tests is.

Only commit when lint, typecheck, format, and tests are all green. Fix red checks before committing, not after.

## Review Pass

When implementation is complete, detect which stacks were touched and run the appropriate reviewers:

- Python/FastAPI changed → `/nunchuck-skills:python-review`
- React/TypeScript changed → `/nunchuck-skills:react-review`
- Rails changed → `/nunchuck-skills:rails-review`
- Schema or queries changed → `/nunchuck-skills:data-review`

Address everything the reviewers surface. Re-run until clean.

## Hand Off

Give a QA plan: what to manually verify, in what order, and what edge cases to hit.

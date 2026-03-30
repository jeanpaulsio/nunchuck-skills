---
name: ship-confident
description: Daily/weekly/monthly audit cadences for code quality and test health. Produces actionable findings, not observations.
---

# Ship Confident

Audit cadences to keep your codebase healthy. Each produces actionable findings ranked by effort and impact.

## Code Quality

### Daily (on code you just changed)

1. **Duplication** -- Did I write something that already exists? Only extract at 3+ occurrences.
2. **Coupling** -- Can this be tested in isolation?
3. **Naming** -- Understandable without surrounding context?
4. **Testability** -- Hard to test = too coupled.
5. **Decision proximity** -- Is the logic close to the data it needs?

### Weekly (across recent PRs)

1. **Repeated patterns** -- Same shape in 3+ files? Extraction candidate.
2. **Hot files** -- Most modified = most fragile.
3. **Growing files** -- Over 400 lines? Accumulating concerns.
4. **Inconsistent solutions** -- Same problem, different approaches. Pick one.
5. **Redundant deps** -- New library overlaps with existing one?

Each finding: affected files, proposed action, effort (S/M/L), pain rank (high/med/low).

### Monthly (codebase shape)

1. **Onboarding friction** -- Could a new contributor understand this in a day?
2. **File sizes** -- List all over 400 lines. Prioritize by churn.
3. **God components/classes** -- 5+ behavior-controlling props = too much.
4. **Copy-paste vs compose** -- Where are we copying? (Only extract at 3+.)
5. **Library coupling** -- Tightly coupled to something we might swap?
6. **Naming drift** -- Same concept, different names in different places?

Output: ranked backlog grouped into this sprint / next sprint / track but don't act.

## Test Health

### Daily (on tests you just wrote)

1. **Implementation coupling** -- Breaks on refactor without behavior change?
2. **Mock count** -- More than 2 mocks? Unit under test has too many deps.
3. **User actions** -- Tests what a user does, or what the code does internally?
4. **Error paths** -- Tested what happens on failure?
5. **Real boundaries** -- Mocking something you should hit for real?

### Weekly (test suite)

1. **Brittle tests** -- Broke without behavior change? Testing implementation.
2. **Redundant coverage** -- Integration re-testing unit-tested code? Cut overlap.
3. **Missing gaps** -- Code changed without tests? Worth adding?
4. **Never-failing** -- Hasn't failed in months? Check it would fail if the feature broke.

### Monthly (coverage and confidence)

1. **Uncovered critical paths** -- Most important user flows tested e2e?
2. **Integration vs unit** -- "Integration tests" that are really unit tests with extra setup?
3. **CI protection** -- Critical flows in CI, not just local?

## Using the Output

- **Daily:** Fix inline if under 5 min. Otherwise note it.
- **Weekly:** Ticket high-pain items. Fix S-sized items in PRs that touch affected files.
- **Monthly:** Feed into sprint planning as the refactoring roadmap.

If something has been "track but don't act" for 3 months without causing pain, delete it.

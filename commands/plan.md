---
description: Product thinking + systems design before writing code. Walks through nouns, relationships, states, and scope before touching implementation.
---

# Plan

Before writing any code, work through the planning modes:

1. **Scout** (if starting on a new codebase):
   - Use the **codebase-assessor** agent to understand the current state
   - Skip if you already know the codebase well

2. **Product Think** (for new features or new projects):
   - Use the **product-thinker** agent to extract requirements through conversation
   - Identify nouns, relationships, state transitions, and edge cases
   - Define v1 scope and what to defer
   - WAIT for user confirmation before proceeding

3. **Design** (after product decisions are clear):
   - Translate nouns into tables, relationships into FKs, lifecycles into status enums
   - Define API contracts (request/response shapes)
   - Identify service boundaries
   - Present the design for user approval

4. **Implementation plan**:
   - Break into ordered steps: migration → model → service → route → frontend
   - For each step: what changes, what files are affected, what tests are needed
   - Identify risks: what could go wrong, what assumptions are we making
   - Identify dependencies: what needs to exist before this step can start
   - Flag anything that touches shared code (migrations, core models, auth)
   - Estimate scope: is this a single PR or should it be broken into multiple
   - WAIT for user CONFIRM before writing any code

For refactors and bug fixes where product thinking isn't needed, skip steps 1-3 and go straight to the implementation plan. Still break it down, still identify risks, still wait for confirmation.

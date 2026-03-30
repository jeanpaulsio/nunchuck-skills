---
description: Product thinking + systems design before writing code. Walks through nouns, relationships, states, and scope before touching implementation.
---

# Plan

Before writing any code, work through the planning modes:

1. **Assess** (if starting on a new codebase):
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
   - Identify risks and dependencies
   - WAIT for user CONFIRM before writing any code

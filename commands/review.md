---
description: Stack-aware code review. Detects the stack from changed files and runs the appropriate reviewer agent.
---

# Code Review

Review changed code using the appropriate stack reviewer:

1. Get changed files: `git diff --name-only`

2. Detect stack from file extensions:
   - `.py` files → use **python-reviewer** agent
   - `.ts`, `.tsx`, `.js`, `.jsx` files → use **react-typescript-reviewer** agent
   - `.rb`, `.erb` files → use **rails-reviewer** agent

3. If migration files are present, also run the **database-reviewer** agent

4. For each reviewer, generate a severity report with file locations and fixes

5. Block if CRITICAL or HIGH issues found

---
description: Ruby on Rails code review with severity-based filtering
---

# Rails Review

1. Get changed files: `git diff --name-only -- '*.rb' '*.erb'`
2. Run the **rails-reviewer** agent on changed files
3. Generate severity report with file locations and fixes
4. Block if CRITICAL or HIGH issues found

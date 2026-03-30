---
description: React/TypeScript code review with severity-based filtering
---

# React Review

1. Get changed files: `git diff --name-only -- '*.ts' '*.tsx' '*.js' '*.jsx'`
2. Run the **react-typescript-reviewer** agent on changed files
3. Generate severity report with file locations and fixes
4. Block if CRITICAL or HIGH issues found

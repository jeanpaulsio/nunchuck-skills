---
description: Python/FastAPI/SQLAlchemy code review with severity-based filtering
---

# Python Review

1. Get changed Python files: `git diff --name-only -- '*.py'`
2. Run the **python-reviewer** agent on changed files
3. Generate severity report with file locations and fixes
4. Block if CRITICAL or HIGH issues found

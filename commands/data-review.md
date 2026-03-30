---
description: Database schema and query review. Checks for missing indexes, unsafe migrations, schema smells, and query anti-patterns.
---

# Data Review

Run the **database-reviewer** agent on the current codebase:

1. Read all model/migration files
2. Check for schema design issues (boolean soup, naming, missing constraints)
3. Review recent migration files for safety (lock-awareness, enum handling)
4. Scan query patterns for performance issues (SELECT *, random(), N+1)
5. Generate severity report with recommendations

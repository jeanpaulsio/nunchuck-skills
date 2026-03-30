---
name: python-fastapi-checklist
description: Pre-commit checklist for Python / FastAPI / SQLAlchemy projects
---

# Python / FastAPI Checklist

## Pre-Commit (every time, no exceptions)

```bash
ruff check app/ tests/
ruff format --check app/ tests/
mypy app/ --ignore-missing-imports
pytest tests/ -v
```

## Review (after implementation)

- [ ] Routes are thin -- validation and delegation only
- [ ] Services raise domain exceptions, not `HTTPException`
- [ ] Services use `flush()`, not `commit()`
- [ ] Error responses use consistent envelope
- [ ] Pydantic schemas validate all input
- [ ] List queries use explicit column selection (no TEXT fields)
- [ ] Migrations reviewed for false positives
- [ ] Enums use raw SQL, not `sa.Enum.create()`
- [ ] Tests cover happy path + at least one error path
- [ ] `expire_on_commit=False` on async session factory

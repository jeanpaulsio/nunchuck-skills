---
name: ruby-rails-checklist
description: Pre-commit checklist for Ruby on Rails projects
---

# Ruby on Rails Checklist

## Pre-Commit (every time, no exceptions)

```bash
bin/rubocop
bin/rails test
```

## Review (after implementation)

- [ ] Controllers are thin -- 7 REST actions only
- [ ] `params.expect` (not `require.permit`) for param filtering
- [ ] `status: :unprocessable_entity` on form validation failure
- [ ] `status: :see_other` on POST/DELETE redirects
- [ ] No business logic in callbacks (use service objects)
- [ ] DB unique constraint backs model uniqueness validation
- [ ] Jobs have `retry_on` configured (Solid Queue doesn't retry by default)
- [ ] Jobs are idempotent (check-before-act pattern)
- [ ] Migrations safe for zero-downtime (`strong_migrations` rules)
- [ ] User-owned resources scoped to `current_user`
- [ ] Enum values are strings, not integers

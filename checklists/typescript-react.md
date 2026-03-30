---
name: typescript-react-checklist
description: Pre-commit checklist for TypeScript / React projects
---

# TypeScript / React Checklist

## Pre-Commit (every time, no exceptions)

```bash
npm run lint
npm run typecheck    # tsc --noEmit
npm test
```

## Review (after implementation)

- [ ] Components under 400 lines
- [ ] All interactive elements have `cursor-pointer`
- [ ] Loading, error, and empty states handled
- [ ] Works on mobile (375px width)
- [ ] One scroll container per route (no nested scroll)
- [ ] `min-h-0` on flex parents of scrollable children
- [ ] Query keys use the factory pattern
- [ ] Mutations invalidate the right caches
- [ ] Mock objects typed with their interface
- [ ] `tsc --noEmit` run on test files (vitest ignores type errors)
- [ ] Enter-to-submit inputs show a hint

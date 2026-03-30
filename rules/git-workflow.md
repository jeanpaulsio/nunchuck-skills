---
name: git-workflow
description: Git conventions for commits, branches, and PRs. Conventional commits, branch-and-PR always, never push to main.
---

# Git Workflow

## Never Push to Main

Always:
1. Create a branch (`git checkout -b feat/...` or `fix/...`)
2. Commit to the branch
3. Open a PR

No exceptions. Not for one-line fixes, not for typos, not for anything.

## Commit Message Format

```
<type>: <description>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`

Keep the description short (under 70 characters). Use the body for context when needed.

## Branch Naming

```
feat/add-booking-service
fix/scroll-overflow-mobile
refactor/split-review-service
chore/update-dependencies
```

## Pull Request Workflow

When creating PRs:
1. Look at the full commit history for the branch, not just the last commit (`git diff main...HEAD`)
2. Write a summary that covers ALL changes in the branch
3. Include a test plan
4. Push with `-u` flag if it's a new branch

## Research Before Building

Before implementing anything new:
1. Search GitHub for existing implementations (`gh search code`, `gh search repos`)
2. Check library docs for the specific API/pattern you need
3. Search package registries (npm, PyPI, rubygems) before hand-rolling utilities
4. Prefer battle-tested libraries over custom code when they fit

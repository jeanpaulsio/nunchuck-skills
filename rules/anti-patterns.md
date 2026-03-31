---
name: anti-patterns
description: Hard-won lessons from real mistakes -- patterns that looked right but cost significant time to fix
---

# Anti-Patterns

Lessons learned from shipping 1,200+ commits. Each one cost real time to discover and fix.

## Research Before You Build

**The mistake:** Choosing HttpOnly cookies for auth on day 1 without checking if the deployment target (Render) supports cross-origin cookies.

**The cost:** 8+ fix commits, 2 full reverts, and a complete rewrite to tokens-in-body on day 1.

**The lesson:** Before implementing any infrastructure decision (auth, storage, caching, deployment), research the platform constraints. 20 minutes of reading Render's docs would have saved 4 hours of debugging.

**Check:**
- Does your hosting platform support the pattern? (cookies, websockets, file storage)
- What are the CORS constraints between your frontend and backend origins?
- What connection limits does your database plan impose?

## Wrong Abstraction Over No Abstraction

**The mistake:** Building a JavaScript-based `ScaleToFit` component to measure and scale SVG visualizations, then iterating on it for 7+ commits before realizing SVG's native `viewBox` attribute does this automatically.

**The cost:** 7 fix commits, a revert, and a complete replacement with a one-line viewBox solution.

**The lesson:** Before building a custom solution, check if the platform already handles it. SVGs scale natively. CSS handles most responsive layouts. The browser's built-in dialog element does modals. Custom code should fill gaps, not replace existing capabilities.

**Check:**
- Does the platform/technology already have a native solution?
- Am I fighting the framework or working with it?
- Is this abstraction earning its complexity?

## Desktop-First, Mobile-Later

**The mistake:** Building every feature for desktop, then fixing mobile as a follow-up. This created 30+ mobile-specific fix commits spread across every single day of development.

**The cost:** Death by a thousand cuts. No single fix was large, but the cumulative time spent on mobile remediation was significant.

**The lesson:** Start with mobile constraints. A layout that works on 375px wide screens will work on desktop. The reverse is rarely true.

**Check:**
- Does this layout work on a phone?
- Are touch targets at least 44x44px?
- Does the modal/overlay work without a mouse?

## Test Backfill Instead of Test-With

**The mistake:** Shipping features without tests, then doing a massive dedicated test backfill sprint (75% to 91.5% coverage in one push with 1,110 tests across ~20 sequential commits).

**The cost:** The backfill itself was fine, but the features shipped between "build" and "backfill" had a 2.2:1 fix-to-feat ratio. Many of those fixes would have been caught by tests written alongside the feature.

**The lesson:** Write the test with the feature. A test written after the fact validates what you built. A test written before the implementation validates what you intended. The gap between those two is where bugs live.

## Implement Then Review (The 2:1 Fix Ratio)

**The mistake:** Building a feature, running a code review agent, then fixing the findings. This pattern appeared ~30 times in 10 days: `feat: add X` followed by `fix: address review findings` followed by more fixes.

**The cost:** 59% of all commits were fixes. The review agent consistently caught issues that should have been addressed in the first implementation pass.

**The lesson:** The review agent isn't a safety net for sloppy first passes. It's a second pair of eyes. If it consistently catches the same categories of issues (missing error handling, mobile layout, type safety), add those to your mental checklist and catch them during implementation, not after.

## Boolean Soup in Schema Design

**The mistake:** Using multiple boolean columns instead of a status enum.

```
is_active, is_archived, is_completed, is_paid
```

**The cost:** Impossible states (`is_completed = true AND is_active = false AND is_paid = true` -- what does that mean?), complex WHERE clauses, and confusing queries.

**The lesson:** If a thing has a lifecycle with defined states, use a single status enum column. Booleans are for binary properties that are truly independent of each other (`is_public` is fine -- it's not part of a lifecycle).

## Shipping Without Assessing Platform Constraints

A recurring theme: building first, discovering constraints second.

- Auth: HttpOnly cookies don't work cross-origin on Render
- SVG: Custom JavaScript scaling instead of native viewBox
- Sentry: `replayIntegration` blocks all pointer events
- Page transitions: CSS animations conflict with Vike SSR
- CI path filtering: Broke the pipeline, reverted immediately
- NODE_ENV=production: PaaS sets this, `npm ci` skips devDependencies, build tools vanish
- SSR deployment: SSR apps need a running web service, not static hosting -- static deploy serves an empty shell

**The pattern:** Every revert in the commit history traces back to insufficient research before implementation.

**The fix:** `/scout` exists for this reason. 10 minutes of platform research prevents an hour of debugging and a revert.

## PaaS Deployment Traps

**The mistake:** Putting build tools (`vite`, `typescript`, `tailwindcss`) in `devDependencies` and deploying to a PaaS that sets `NODE_ENV=production`.

**The cost:** `npm ci` silently skips devDependencies. Build fails. You add `--include=dev` to the build command but the env var overrides it.

**The lesson:** If `npm run build` needs it, it goes in `dependencies`. Only test-only tools (`vitest`, `@testing-library`) go in `devDependencies`. This applies to Render, Heroku, Railway, Fly, and any PaaS that sets `NODE_ENV=production`.

## SQLite Is Not Postgres

**The mistake:** Running tests against SQLite "for speed" and deploying to Postgres.

**The cost:** SQLite silently ignores enum constraints, foreign key enforcement (off by default), row-level locking, and type mismatches. Tests pass. Production crashes.

**The lesson:** Always test against the same database you deploy to. The 200ms you save per test run is not worth the production incident.

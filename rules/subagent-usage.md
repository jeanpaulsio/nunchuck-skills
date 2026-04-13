# Sub-Agent Usage

## Default: Do It Inline

Sequential work in the main context is almost always faster than
spawning sub-agents. Every sub-agent pays a fixed cost: fresh context,
re-reading CLAUDE.md, re-exploring the codebase, then the parent waits
for the slowest one and has to merge their outputs back in.

**Default to inline.** Work on tasks sequentially in the main context,
reusing prior file reads and exploration.

## When Sub-Agents Pay Off

Only delegate when ALL of these are true:
1. The subtask is genuinely heavy (multi-minute of real work)
2. It's truly independent -- no overlapping files, no shared context
3. Either: (a) you need the isolation, or (b) the output would
   pollute the parent's context with noise

Good fits: codebase-wide research across many files, security audits,
dedicated reviewers that need a clean context.

Bad fits: "write these 4 related files", "run these 3 quick searches",
"do this task step by step". Do these inline.

## Never Parallel-Spawn Small Tasks

If a task takes under ~2 minutes of real work, it's faster inline.
Do not spawn parallel agents for small tasks just because they're
independent -- the overhead dominates.

## Explicitly Sequential

When the user says "one at a time" or "sequentially", honor that at
the agent-spawn level too -- do not spawn multiple sub-agents in
parallel even if the individual steps look independent.

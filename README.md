# Nunchuck Skills

> "You know, like nunchuck skills, bo hunting skills, claude code skills. Girls only want boyfriends who have great skills."

A practical engineering playbook for Claude Code. Born from shipping 1,200+ commits, making real mistakes, and learning what actually matters before you write code.

This isn't a collection of generic best practices Claude already knows. It's a workflow system grounded in patterns that survived contact with production.

## What's in here

```
nunchuck-skills/
├── commands/                        # Slash commands (triggers)
│   ├── plan.md                      # /plan - product think + systems design
│   ├── review.md                    # /review - stack-aware code review
│   ├── assess.md                    # /assess - codebase assessment
│   ├── audit.md                     # /audit - ship confident cadences
│   └── data-review.md               # /data-review - schema + query review
│
├── agents/                          # Agent definitions (the brains)
│   ├── product-thinker.md           # Conversational requirements extraction
│   ├── codebase-assessor.md         # Stack, schema, test, churn analysis
│   ├── python-reviewer.md           # Python/FastAPI/SQLAlchemy review
│   ├── react-typescript-reviewer.md # React/TypeScript/Vike review
│   ├── rails-reviewer.md            # Ruby on Rails 8 review
│   └── database-reviewer.md         # PostgreSQL schema + query review
│
├── skills/                          # Deep reference (the knowledge base)
│   ├── workflow.md                  # 5 modes: assess, think, design, build, audit
│   ├── ship-confident.md            # Daily/weekly/monthly audit cadences
│   ├── python-fastapi-patterns/
│   │   └── SKILL.md                 # FastAPI + SQLAlchemy + Pydantic patterns
│   ├── react-typescript-patterns/
│   │   └── SKILL.md                 # React 19 + Vike + TanStack Query patterns
│   ├── rails-patterns/
│   │   └── SKILL.md                 # Rails 8 + Hotwire + Solid Queue patterns
│   └── database-patterns/
│       └── SKILL.md                 # PostgreSQL schema, query, migration patterns
│
├── rules/                           # Always-loaded guardrails
│   ├── anti-patterns.md             # Hard-won lessons from real mistakes
│   └── ux-patterns.md               # Scroll architecture, touch targets, mobile layout
│
└── checklists/                      # Pre-commit checklists
    ├── python-fastapi.md
    ├── typescript-react.md
    └── ruby-rails.md
```

## Architecture

Three layers:

1. **Commands** trigger agents via slash commands (`/review`, `/plan`, `/assess`)
2. **Agents** run review/analysis with severity-based filtering and structured output
3. **Skills** provide the deep reference patterns agents draw from

Plus **rules** (always-loaded guardrails) and **checklists** (pre-commit gates).

## The 5 Modes

| Mode | What it does | When to use |
|------|-------------|-------------|
| **Assess** | Understand the codebase or pick a stack | Starting any project |
| **Product Think** | Extract nouns, relationships, states from conversation | Before writing any code |
| **Design** | Schema, API contracts, service boundaries | After product decisions are made |
| **Build** | TDD loop with review | The actual coding |
| **Audit** | Daily/weekly/monthly hygiene | Ongoing maintenance |

Most playbooks start at Build. That's why most code built on vibes breaks.

## Install

```bash
git clone https://github.com/jeanpaulsio/nunchuck-skills.git
cd nunchuck-skills

# Install to current project (recommended)
./install.sh

# Install globally (applies to all projects)
./install.sh --global
```

## Stack Support

All three stacks included in this repo:

- **Python / FastAPI / SQLAlchemy** -- patterns, reviewer agent, checklist
- **TypeScript / React / Vike** -- patterns, reviewer agent, checklist
- **Ruby on Rails 8** -- patterns, reviewer agent, checklist
- **PostgreSQL** -- database patterns and reviewer (cross-stack)

## Philosophy

- The person describes their world. The system translates it into engineering decisions.
- Only include things Claude genuinely doesn't know or gets wrong without guidance.
- Only extract patterns when they appear 3+ times.
- Write tests with features, not after.
- Your CLAUDE.md is more valuable than any generic skill.

## Credits

Built by [@jeanpaulsio](https://github.com/jeanpaulsio) from real engineering, real mistakes, and real lessons learned.

Inspired by: Sandi Metz (The Wrong Abstraction), Kent C. Dodds (AHA Programming), Dan Abramov (Goodbye Clean Code), Google Engineering Practices.

# Nunchuck Skills

> "You know, like nunchuck skills, bo hunting skills, claude code skills. Girls only want boyfriends who have great skills."

A practical engineering playbook for Claude Code. Born from shipping 1,200+ commits, making real mistakes, and learning what actually matters before you write code.

This isn't a collection of generic best practices Claude already knows. It's a workflow system grounded in patterns that survived contact with production.

## What's in here

```
nunchuck-skills/
├── commands/                     # Slash commands (triggers)
│   ├── plan.md                   # /plan - product think + systems design
│   ├── review.md                 # /review - stack-aware code review
│   ├── assess.md                 # /assess - codebase assessment
│   ├── audit.md                  # /audit - ship confident cadences
│   └── data-review.md            # /data-review - schema + query review
│
├── agents/                       # Agent definitions (the brains)
│   ├── product-thinker.md        # Conversational requirements extraction
│   ├── codebase-assessor.md      # Stack, schema, test, churn analysis
│   ├── python-reviewer.md        # Python/FastAPI/SQLAlchemy code review
│   ├── database-reviewer.md      # Schema design + query pattern review
│   └── security-reviewer.md      # OWASP + config scanning
│
├── skills/                       # Deep reference (the knowledge base)
│   ├── workflow.md               # 5 modes with war stories
│   ├── python-fastapi-patterns/
│   │   └── SKILL.md              # FastAPI + SQLAlchemy + Pydantic patterns
│   ├── database-patterns/
│   │   └── SKILL.md              # Schema, query, migration patterns
│   └── ship-confident.md         # Audit cadences
│
├── rules/                        # Always-loaded guardrails
│   ├── data-layer.md             # Schema design principles
│   └── anti-patterns.md          # Hard-won lessons from real mistakes
│
└── checklists/                   # Pre-commit checklists
    ├── python-fastapi.md
    ├── typescript-react.md
    └── ruby-rails.md
```

## Architecture

Three layers, same pattern as [claude-react-typescript](https://github.com/jeanpaulsio/claude-react-typescript) and [claude-rails](https://github.com/jeanpaulsio/claude-rails):

1. **Commands** trigger agents via slash commands
2. **Agents** run the review/analysis with severity-based filtering
3. **Skills** provide the deep reference patterns agents draw from

Plus **workflow** (the 5 modes) and **rules** (always-loaded guardrails).

## The 5 modes

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

### Manual install

```bash
# Local (current project only)
cp -r commands/ .claude/commands/nunchuck-skills/
cp -r agents/ .claude/agents/nunchuck-skills/
cp -r skills/ .claude/skills/nunchuck-skills/
cp -r rules/ .claude/rules/nunchuck-skills/

# Global (all projects)
cp -r commands/ ~/.claude/commands/nunchuck-skills/
cp -r agents/ ~/.claude/agents/nunchuck-skills/
cp -r skills/ ~/.claude/skills/nunchuck-skills/
cp -r rules/ ~/.claude/rules/nunchuck-skills/
```

## Philosophy

- The person describes their world. The system translates it into engineering decisions.
- Only include things Claude genuinely doesn't know or gets wrong without guidance.
- Only extract patterns when they appear 3+ times.
- Write tests with features, not after.
- Your CLAUDE.md is more valuable than any generic skill.

## Stack support

The workflow and principles are stack-agnostic. The patterns and checklists are stack-specific:

- **Python / FastAPI / SQLAlchemy** -- included in this repo
- **TypeScript / React** -- see [claude-react-typescript](https://github.com/jeanpaulsio/claude-react-typescript)
- **Ruby on Rails** -- see [claude-rails](https://github.com/jeanpaulsio/claude-rails)

## Credits

Built by [@jeanpaulsio](https://github.com/jeanpaulsio) from real engineering, real mistakes, and real lessons learned.

Inspired by: Sandi Metz (The Wrong Abstraction), Kent C. Dodds (AHA Programming), Dan Abramov (Goodbye Clean Code), Google Engineering Practices.

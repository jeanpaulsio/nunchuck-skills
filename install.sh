#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Determine install target
if [[ "${1:-}" == "--global" ]]; then
  TARGET="$HOME/.claude"
  echo "Installing nunchuck-skills globally to ~/.claude/"
else
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  TARGET="$PROJECT_ROOT/.claude"
  echo "Installing nunchuck-skills locally to $TARGET/"
fi

# Create directories
mkdir -p "$TARGET/commands/nunchuck-skills"
mkdir -p "$TARGET/agents/nunchuck-skills"
mkdir -p "$TARGET/skills/nunchuck-skills"
mkdir -p "$TARGET/rules/nunchuck-skills"

# Copy commands (if they exist)
if [ -d "$SCRIPT_DIR/commands" ] && [ "$(ls -A "$SCRIPT_DIR/commands/"*.md 2>/dev/null)" ]; then
  cp "$SCRIPT_DIR/commands/"*.md "$TARGET/commands/nunchuck-skills/"
fi

# Copy agents (if they exist)
if [ -d "$SCRIPT_DIR/agents" ] && [ "$(ls -A "$SCRIPT_DIR/agents/"*.md 2>/dev/null)" ]; then
  cp "$SCRIPT_DIR/agents/"*.md "$TARGET/agents/nunchuck-skills/"
fi

# Copy skills (preserving directory structure)
if [ -d "$SCRIPT_DIR/skills" ]; then
  cp -r "$SCRIPT_DIR/skills/"* "$TARGET/skills/nunchuck-skills/"
fi

# Copy rules
if [ -d "$SCRIPT_DIR/rules" ]; then
  cp "$SCRIPT_DIR/rules/"*.md "$TARGET/rules/nunchuck-skills/"
fi

# Copy checklists into rules
if [ -d "$SCRIPT_DIR/checklists" ] && [ "$(ls -A "$SCRIPT_DIR/checklists/"*.md 2>/dev/null)" ]; then
  mkdir -p "$TARGET/rules/nunchuck-skills/checklists"
  cp "$SCRIPT_DIR/checklists/"*.md "$TARGET/rules/nunchuck-skills/checklists/"
fi

echo ""
echo "Installed to $TARGET/:"
ls -la "$TARGET/commands/nunchuck-skills/" 2>/dev/null && echo "" || true
ls -la "$TARGET/agents/nunchuck-skills/" 2>/dev/null && echo "" || true
ls -la "$TARGET/skills/nunchuck-skills/" 2>/dev/null && echo "" || true
ls -la "$TARGET/rules/nunchuck-skills/" 2>/dev/null && echo "" || true
echo ""
echo "Ready. Start with: \"/scout\" or \"/plan\""

---
description: Focused security audit for application code and Claude Code config. Use before launches or after adding auth/payments.
---

# Security Review

Run the **security-reviewer** agent for a deep security audit.

This is separate from the stack-specific reviewers (`/python-review`, `/react-review`, `/rails-review`) which already check for common security issues on every review. Use this for dedicated audits before launches or after implementing sensitive features.

Covers: secrets, auth, authorization, input validation, output safety, dependency vulnerabilities, and Claude Code config.

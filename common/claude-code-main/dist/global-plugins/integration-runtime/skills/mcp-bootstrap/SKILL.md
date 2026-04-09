---
name: mcp-bootstrap
description: Use when installing, registering, or validating MCP servers and related environment variables (paths, tokens, workspace roots).
---

# MCP Bootstrap

Use this skill to bootstrap MCP with reproducible steps.

## Primary behaviors
- Install missing MCP dependencies with explicit package names.
- Generate or patch MCP config blocks with path-safe values.
- Validate startup using tool-specific sanity checks.
- Separate local filesystem/git scope from API-token-protected connectors.

## Trigger examples
- "给这台机器一键装好 MCP"
- "把 config.toml 里的 mcp_servers 全配上"
- "检查 fetch/git/filesystem/playwright 能不能用"

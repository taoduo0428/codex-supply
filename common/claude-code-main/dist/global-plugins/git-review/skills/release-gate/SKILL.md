---
name: release-gate
description: Use when users are about to tag, release, or ship changes and need security, regression, and release-readiness checks.
---

# Release Gate

Use this skill before tagging or publishing changes.

## Primary behaviors
- Run a release-readiness checklist: security, compatibility, tests, rollback notes.
- Highlight high-risk diffs and unresolved TODO/FIXME areas.
- Ensure release notes and tag strategy are coherent.
- Produce a concise go/no-go recommendation with rationale.

## Trigger examples
- "准备发版，先过一遍风险"
- "这个分支可以打 tag 了吗"
- "给我一份上线前检查清单"
